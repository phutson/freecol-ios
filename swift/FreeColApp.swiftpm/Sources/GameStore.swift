//
//  Copyright (C) 2002-2022   The FreeCol Team
//
//  This file is part of FreeCol.
//
//  FreeCol is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 2 of the License, or
//  (at your option) any later version.
//
//  FreeCol is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with FreeCol.  If not, see <http://www.gnu.org/licenses/>.
//

import FreeColCore
import FreeColEngine
import FreeColIO
import FreeColMap
import FreeColResources
import FreeColServer
import Foundation
import Observation
import UIKit

/// The game being shown: the engine running it, the human player's
/// latest snapshot, what the client is doing (the unit being moved, a
/// goto being chosen, a question waiting), and the images to draw it
/// with.
@MainActor @Observable
final class GameStore {
    private(set) var snapshot: GameSnapshot?
    private(set) var images: MapImageStore?
    private(set) var failure: String?
    private var engine: GameEngine?

    /// Whether the engine is busy (the others' turns can take a while).
    private(set) var busy = false
    /// The unit being moved, what it can do, and its way to its
    /// destination.
    private(set) var activeUnitId: String?
    private(set) var actions: UnitActions?
    private(set) var destinationPath: UnitPath?
    /// Choosing a goto destination: the tile tapped and the path to it.
    private(set) var choosingGoto = false
    private(set) var gotoTarget: MapPosition?
    private(set) var gotoPath: UnitPath?
    /// A question the client asks before going on.
    private(set) var question: PlayQuestion?
    private var pending: (action: GameEngine.PlayAction, answers: [String: String])?
    /// What the server asks, one at a time, and what the player is
    /// told.
    private(set) var requests: [ServerRequest] = []
    var notices: [String] = []
    /// A trade with natives under way, at its latest step.
    private(set) var trade: NativeTradeScreen?
    /// A negotiation to show: one the player starts, or a proposal.
    private(set) var negotiation: Negotiation?
    /// What a spy saw of a foreign colony.
    var spiedColony: ColonyScreen?
    /// The messages of this turn, newest last.
    private(set) var messages: [String] = []
    /// The colony being looked at, as its panel shows it.
    private(set) var colony: ColonyScreen?
    /// Europe, when the player is looking at it.
    private(set) var europe: EuropeScreen?
    /// Where ships in Europe could sail for.
    private(set) var destinations: [(id: String, name: String)] = []
    /// The role changes on offer for the units shown in Europe or a
    /// colony.
    private(set) var roles: [String: [RoleChoice]] = [:]

    /// The game's data, bundled with the app.
    static var dataDirectory: URL? {
        Bundle.main.url(forResource: "data", withExtension: nil)
    }

    var hasGame: Bool { engine != nil }

    /// The path to draw: the goto being chosen, or the active unit's.
    var shownPath: UnitPath? { choosingGoto ? gotoPath : destinationPath }

    var activeUnit: UnitSnapshot? { activeUnitId.flatMap { snapshot?.unit($0) } }

    // MARK: Starting

    /// Start a new game, as the setup screen asks.
    func newGame(playerName: String, rules: String, difficulty: String) async {
        await start {
            let data = FreeColDataDirectory(url: $0)
            return try GameEngine(newGame: data, rules: rules, difficulty: difficulty,
                                  playerName: playerName, messages: $1)
        }
    }

    /// Load the bundled saved game.
    func loadSample() async {
        guard let save = Bundle.main.url(forResource: "freecol-commands-seed1", withExtension: "fsg",
                                         subdirectory: "games") else {
            failure = "The sample game is missing from the app."
            return
        }
        await start { try GameEngine(loading: save, messages: $1) }
    }

    private func start(_ make: @escaping @Sendable (URL, MessageBundle) throws -> GameEngine) async {
        guard let data = Self.dataDirectory else {
            failure = "The game's data is missing from the app."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let messages = try GameStore.messages(data)
                return (try make(data, messages), try MapImageStore(dataDirectory: data))
            }.value
            engine = loaded.0
            images = loaded.1
            snapshot = await loaded.0.snapshot()
            await play(.startTurn)
        } catch {
            failure = "Could not start the game: \(error)"
        }
    }

    // MARK: Playing

    /// Do something on the map; a question stops it until answered.
    func play(_ action: GameEngine.PlayAction) async {
        await run(action, answers: [:])
    }

    private func run(_ action: GameEngine.PlayAction, answers: [String: String]) async {
        guard let engine else { return }
        busy = true
        defer { busy = false }
        do {
            let r = try await engine.play(action, answers: answers)
            await apply(r)
            if let q = r.question {
                question = q
                pending = (action, answers)
            }
        } catch {
            notices.append("\(error)")
        }
    }

    /// Answer the question asked, and go on.  The question is taken at
    /// once, before the alert showing it is dismissed.
    func answer(_ choice: String) {
        guard let q = question, let p = pending else { return }
        question = nil
        pending = nil
        var answers = p.answers
        answers[q.id] = choice
        Task { await run(p.action, answers: answers) }
    }

    /// Leave the question unanswered: nothing more is done.
    func dismissQuestion() {
        question = nil
        pending = nil
    }

    /// Answer what the server asked.  The request is taken at once,
    /// before the alert showing it is dismissed; an emigrant chosen of
    /// several owed asks for the next.
    func answer(_ request: ServerRequest, _ answer: RequestAnswer) {
        requests.removeAll { $0 == request }
        Task {
            guard let engine else { return }
            let r = await engine.respond(request, answer)
            await apply(r)
            if case let .emigrate(count, fountain, _, _) = request, count > 1 {
                requests.insert(await engine.emigrationRequest(count: count - 1, fountainOfYouth: fountain), at: 0)
            }
        }
    }

    /// The next step of the native trade.
    /// The trade stays shown until the natives answer, then gives way
    /// to the next step, or closes when there is none.
    func tradeStep(_ choice: NativeTradeChoice) {
        guard let screen = trade else { return }
        Task {
            guard let engine else { return }
            let r = await engine.respond(.nativeTrade(screen), .trade(choice))
            trade = nil
            await apply(r)
        }
    }

    /// The negotiation as its dialog shows it, for the items on the
    /// table.
    func negotiationScreen(_ n: Negotiation, _ items: [TradeOffer], changed: Bool) async -> NegotiationScreen? {
        await engine?.negotiationScreen(n, items: items, changed: changed)
    }

    /// Answer the negotiation with what is on the table.
    func answer(_ n: Negotiation, _ answer: NegotiationAnswer, _ items: [TradeOffer]) {
        negotiation = nil
        self.answer(.negotiation(n), .agreement(answer, items))
    }

    private func apply(_ r: CommandResult) async {
        if r.snapshot.turn != snapshot?.turn { messages = [] }
        snapshot = r.snapshot
        notices += r.notices
        if let refusal = r.refusal { notices.append(refusal) }
        for e in r.events {
            switch e {
            case .message(let m): messages.append(m.text)
            case .request(.nativeTrade(let screen)): trade = screen
            case .request(.negotiation(let n)): negotiation = n
            case .request(let request): requests.append(request)
            case .notice(let text): notices.append(text)
            case .spied(let screen): spiedColony = screen
            case .unitMoved, .attack: break
            }
        }
        if r.activeUnitId != activeUnitId { stopGoto() }
        activeUnitId = r.activeUnitId
        await refreshActiveUnit()
        // Java opens a colony's panel on arriving at or founding it.
        if let id = r.colonyToShow ?? colony?.id {
            colony = await engine?.colonyScreen(id)
        }
        if europe != nil { await refreshEurope() }
        await refreshRoles()
    }

    /// The role changes for the units on screen.
    private func refreshRoles() async {
        guard let engine else { return }
        var ids: [String] = europe?.docks ?? []
        if let c = colony {
            ids += c.outsideUnitIds + c.buildings.flatMap(\.unitIds) + c.tiles.flatMap(\.unitIds)
        }
        var r: [String: [RoleChoice]] = [:]
        for id in ids { r[id] = await engine.roleChoices(id) }
        roles = r
    }

    // MARK: Reports

    /// The reports, while they are shown.
    private(set) var reports: Reports?

    struct Reports {
        let congress: CongressReport
        let religion: [ReligionReport]
        let military: UnitReport
        let naval: UnitReport
    }

    func openReports() async {
        guard let engine else { return }
        reports = Reports(congress: await engine.congressReport(), religion: await engine.religionReport(),
                          military: await engine.unitReport(military: true),
                          naval: await engine.unitReport(military: false))
    }

    func closeReports() {
        reports = nil
    }

    // MARK: Saving and loading

    /// Where saved games are kept: the app's documents, so the Files app
    /// shows them.
    nonisolated static var savesDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// The saved games, newest first.
    nonisolated static var savedGames: [URL] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: savesDirectory, includingPropertiesForKeys: [.contentModificationDateKey]))
            ?? []
        return urls.filter { $0.pathExtension == "fsg" }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
    }

    /// Save the game under a name.
    func save(as name: String) async {
        guard let engine, !name.isEmpty else { return }
        let url = Self.savesDirectory.appendingPathComponent(name).appendingPathExtension("fsg")
        do {
            try await engine.save(to: url)
            notices.append("Saved \(name).")
        } catch {
            notices.append("Could not save: \(error)")
        }
    }

    /// Load a saved game.
    func load(_ url: URL) async {
        await start { try GameEngine(loading: url, messages: $1) }
    }

    // MARK: Europe

    func openEurope() async {
        await refreshEurope()
        await refreshRoles()
    }

    private func refreshEurope() async {
        guard let engine else { return }
        europe = await engine.europeScreen()
        destinations = await engine.sailingDestinations()
    }

    func closeEurope() {
        europe = nil
    }

    // MARK: Colonies

    func openColony(_ id: String) async {
        colony = await engine?.colonyScreen(id)
        await refreshRoles()
    }

    func closeColony() {
        colony = nil
    }

    private func refreshActiveUnit() async {
        guard let engine, let id = activeUnitId else {
            actions = nil
            destinationPath = nil
            return
        }
        actions = await engine.unitActions(id)
        destinationPath = await engine.destinationPath(id)
    }

    /// A tile tapped on the map: choosing a goto, it shows the path
    /// there, and a second tap goes; otherwise a unit of the player's
    /// there is selected (the next one, if the active unit is there),
    /// or the active unit moves to it if it is next door.
    func tap(_ p: MapPosition) async {
        guard let snapshot, question == nil else { return }
        if choosingGoto {
            await chooseGoto(p)
            return
        }
        let tile = snapshot.map.tile(p.x, p.y)
        let mine = (tile?.unitIds ?? []).filter { snapshot.unit($0)?.ownerId == snapshot.playerId }
        // A colony of the player's opens, unless the unit is moving into it.
        if let colony = snapshot.colonies.first(where: { $0.position == p }),
           !(activeUnit?.position.map { a in Direction.allDirections.contains { let s = $0.step(a.x, a.y); return s.x == p.x && s.y == p.y } } ?? false) {
            await openColony(colony.id)
            return
        }
        if let active = activeUnit, let at = active.position, at != p,
           let d = Direction.allDirections.first(where: { let s = $0.step(at.x, at.y); return s.x == p.x && s.y == p.y }) {
            await play(.move(unitId: active.id, direction: d.javaName))
        } else if !mine.isEmpty {
            let next = activeUnitId.flatMap { mine.firstIndex(of: $0) }.map { mine[($0 + 1) % mine.count] } ?? mine[0]
            await play(.select(unitId: next))
        }
    }

    // MARK: Goto

    func startGoto() {
        choosingGoto = activeUnitId != nil
        gotoTarget = nil
        gotoPath = nil
    }

    func stopGoto() {
        choosingGoto = false
        gotoTarget = nil
        gotoPath = nil
    }

    private func chooseGoto(_ p: MapPosition) async {
        guard let engine, let id = activeUnitId else { return }
        if p == gotoTarget, gotoPath != nil {
            stopGoto()
            await play(.goTo(unitId: id, destination: .tile(p)))
            return
        }
        gotoTarget = p
        gotoPath = await engine.gotoPath(id, to: p)
    }

    /// Sail for Europe, by the way the unit would go.
    func goToEurope() async {
        guard let id = activeUnitId else { return }
        stopGoto()
        await play(.goTo(unitId: id, destination: .europe))
    }

    /// The English strings, with the rules' own.
    nonisolated static func messages(_ data: URL) throws -> MessageBundle {
        let strings = data.appendingPathComponent("strings")
        let numberRules = try NumberRules(data: Data(contentsOf: strings.appendingPathComponent("plurals.xml")))
        return MessageBundle.load(directory: strings, languageId: "en_US", numberRules: numberRules,
                                  rulesDirectories: ["classic", "freecol"].map {
                                      data.appendingPathComponent("rules/" + $0)
                                  })
    }
}

/// The map's images: found by key as Java's client finds them (the base
/// data, then the default rules' images), and loaded from their files
/// once each.
final class MapImageStore: @unchecked Sendable {
    let lookup: ResourceMapImages
    private var cache: [MapImage: UIImage] = [:]
    private let lock = NSLock()

    init(dataDirectory data: URL) throws {
        let manager = ResourceManager()
        if let base = try FreeColDataFile(directory: data.appendingPathComponent("base"))
            .resourceMapping(languageId: "en_US") {
            manager.setBase(base)
        }
        manager.setTc(try FreeColTcFile.resourceMapping(dataDirectory: data, id: "default", languageId: "en_US"))
        lookup = ResourceMapImages(manager)
    }

    private var composites: [String: UIImage] = [:]

    /// The picture for an image, or nil if there is none.
    func image(_ image: MapImage) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return loaded(image)
    }

    private func loaded(_ image: MapImage) -> UIImage? {
        if let cached = cache[image] { return cached }
        guard let resource = lookup.manager.imageResource(image.key)?.variation(image.variation),
              let url = resource.locator?.fileURL,
              let loaded = UIImage(contentsOfFile: url.path) else { return nil }
        cache[image] = loaded
        return loaded
    }

    /// The picture Java makes for a composite, made once per key and
    /// variation, as Java caches them.
    func image(_ composite: MapComposite) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        let key = composite.key + "#" + String(composite.variation)
        if let cached = composites[key] { return cached }
        let made = render(composite.picture)
        composites[key] = made
        return made
    }

    private static let tileSize = CGSize(width: MapScene.tileWidth, height: MapScene.tileHeight)

    /// Draw a picture on a clear tile (ImageUtils and the image creators).
    private func render(_ picture: MapPicture) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = MapImageStore.tileSize
        switch picture {
        case let .image(image):
            // Java's image creators take every image at a tile's size.
            guard let i = loaded(image) else { return nil }
            if i.size == size && i.scale == 1 { return i }
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                context.cgContext.interpolationQuality = .high
                i.draw(in: CGRect(origin: .zero, size: size))
            }
        case let .masked(content, mask):
            guard let c = render(content), let m = render(mask) else { return nil }
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                c.draw(at: .zero)
                m.draw(at: .zero, blendMode: .destinationIn, alpha: 1)
            }
        case let .layers(layers):
            let rendered = layers.map { (render($0.picture), CGFloat($0.opacity)) }
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                for (image, alpha) in rendered { image?.draw(at: .zero, blendMode: .normal, alpha: alpha) }
            }
        case let .enlarged(mask):
            guard let m = render(mask) else { return nil }
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                context.cgContext.interpolationQuality = .high
                let w = size.width * 1.25, h = size.height * 1.25
                m.draw(in: CGRect(x: -(w - size.width) / 2, y: -(h - size.height) / 2, width: w, height: h))
                m.draw(at: .zero)
            }
        }
    }
}
