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

import Foundation
import FreeColCore

// What Java's reports show, as plain values made on the player's copy of
// the game.

/// The Continental Congress (ReportContinentalCongressPanel).
public struct CongressReport: Sendable, Equatable {
    /// The father being recruited, by identifier and name.
    public let currentId: String?
    public let currentName: String?
    /// The liberty gathered towards him, and his cost.
    public let liberty: Int
    public let cost: Int
    /// The colonies' liberty production, by goods type.
    public let production: [GoodsAmount]
    /// Every father, in the rules' order.
    public let fathers: [FatherState]
}

public struct FatherState: Sendable, Equatable {
    public let id: String
    public let name: String
    /// Java's type name (TRADE, EXPLORATION...) and its translation.
    public let type: String
    public let typeName: String
    /// "Elected: Autumn 1615", "recruiting", or "available".
    public let state: String
}

/// Religion (ReportReligiousPanel): for each immigration goods type, the
/// immigration needed, held and made, and the colonies with a building
/// making it.
public struct ReligionReport: Sendable, Equatable {
    public let typeId: String
    public let required: Int
    public let immigration: Int
    public let production: Int
    /// The colony and its building's type.
    public let colonies: [(colonyId: String, buildingTypeId: String)]

    public static func == (a: ReligionReport, b: ReligionReport) -> Bool {
        a.typeId == b.typeId && a.required == b.required && a.immigration == b.immigration
            && a.production == b.production && a.colonies.map { "\($0) \($1)" } == b.colonies.map { "\($0) \($1)" }
    }
}

/// The military or naval report (ReportUnitPanel): the forces by type
/// and role, most first, the REF's, and the units by where they are.
public struct UnitReport: Sendable, Equatable {
    public let forces: [UnitCount]
    public let ref: [UnitCount]
    public let places: [UnitsAt]
}

public struct UnitCount: Sendable, Equatable {
    public let typeId: String
    public let roleId: String
    public let number: Int

    /// The type and role as the player reads them ("Veteran Soldier",
    /// "Dragoon").
    public let typeName: String
    public let roleName: String

    init(typeId: String, roleId: String, number: Int) {
        self.typeId = typeId
        self.roleId = roleId
        self.number = number
        typeName = Messages.name(typeId)
        roleName = Messages.name(roleId)
    }
}

public struct UnitsAt: Sendable, Equatable {
    /// Where, as the player names it.
    public let name: String
    public let unitIds: [String]
}

extension PlayerView {

    func congressReport() -> CongressReport {
        let spec = game.specification
        let current = player.currentFather
        let production = (spec?.libertyGoodsTypeList ?? []).map { gt in
            GoodsAmount(typeId: gt.id ?? "", amount: player.colonyList.reduce(0) { $0 + $1.netProduction(of: gt) })
        }
        let elections = player.electionTurns
        let fathers = (spec?.foundingFathers ?? []).map { f -> FatherState in
            let turn = player.hasFather(f) ? elections[Messages.nameKey(f.id)] : nil
            let state = turn.map { t in
                Messages.message(StringTemplate.template("report.continentalCongress.elected")
                    .addStringTemplate("%turn%", t.label(spec?.turnCalendar ?? .standard))) ?? ""
            } ?? (f === current ? "recruiting" : "available")
            return FatherState(id: f.id ?? "", name: Messages.name(f), type: f.type?.javaName ?? "",
                               typeName: f.type.map { Messages.message($0.typeKey) } ?? "", state: state)
        }
        return CongressReport(currentId: current?.id, currentName: current.map { Messages.name($0) },
                              liberty: player.liberty, cost: player.totalFoundingFatherCost,
                              production: production, fathers: fathers)
    }

    func religionReport() -> [ReligionReport] {
        (game.specification?.immigrationGoodsTypeList ?? []).map { gt in
            ReligionReport(typeId: gt.id ?? "", required: player.immigrationRequired, immigration: player.immigration,
                           production: player.totalImmigrationProduction,
                           colonies: player.colonyList.compactMap { c in
                               guard let b = c.workLocations(producing: gt).first as? Building else { return nil }
                               return (c.id ?? "", b.type?.id ?? "")
                           })
        }
    }

    /// The military (land) or naval report.
    func unitReport(military: Bool) -> UnitReport {
        unitReport(military ? .military : .naval)
    }

    /// The military, naval or cargo report (ReportUnitPanel and its
    /// subclasses).
    func unitReport(_ kind: UnitReportKind) -> UnitReport {
        let military = kind == .military
        var whereAt: [ObjectIdentifier: (any Location, [FreeColCore.Unit])] = [:]
        var forces: [UnitCount] = []
        for u in player.units {
            let reportable = switch kind {
            case .military: !u.isNaval && (u.hasAbility(Ability.expertSoldier) || u.isOffensiveUnit)
            case .naval: u.isNaval
            case .cargo: u.isCarrier || u.canCarryTreasure
            }
            guard reportable, let loc = u.location?.up() else { continue }
            whereAt[ObjectIdentifier(loc as AnyObject), default: (loc, [])].1.append(u)
            let type = u.type?.id ?? "", role = u.role?.id ?? ""
            if let i = forces.firstIndex(where: { $0.typeId == type && $0.roleId == role }) {
                forces[i] = UnitCount(typeId: type, roleId: role, number: forces[i].number + 1)
            } else {
                forces.append(UnitCount(typeId: type, roleId: role, number: 1))
            }
        }
        func byNumber(_ list: [UnitCount]) -> [UnitCount] {
            list.enumerated().sorted { a, b in
                a.element.number > b.element.number || (a.element.number == b.element.number && a.offset < b.offset)
            }.map(\.element)
        }
        let spec = game.specification
        let ref = byNumber((player.refUnits ?? []).compactMap { au in
            guard kind != .cargo, let type = au.type(spec!), type.isNaval != military else { return nil }
            return UnitCount(typeId: au.id ?? "", roleId: au.roleId ?? "", number: au.number)
        })

        // Colonies by name, then Europe, then the rest by identifier.
        var order: [any Location] = whereAt.values.map(\.0)
            .filter { !($0 is Colony || $0 is Europe) }
            .sorted { ($0.id ?? "") < ($1.id ?? "") }
        if let europe = player.europe { order.insert(europe, at: 0) }
        let colonies = player.colonyList.sorted {
            ($0.name ?? "").compare($1.name ?? "", options: [.caseInsensitive, .diacriticInsensitive],
                                   locale: Locale(identifier: "en_US")) == .orderedAscending
        }
        order.insert(contentsOf: colonies as [any Location], at: 0)
        var places: [UnitsAt] = []
        for loc in order {
            let present = whereAt[ObjectIdentifier(loc as AnyObject)]?.1 ?? []
            if !military && present.isEmpty { continue }
            let sorted = present.sorted { a, b in
                let c = FreeColObject.compareIds(a.type, b.type)
                if c != 0 { return c < 0 }
                let ra = a.role?.roleIndex ?? 0, rb = b.role?.roleIndex ?? 0
                if ra != rb { return ra < rb }
                return FreeColObject.compareIds(a, b) < 0
            }
            places.append(UnitsAt(name: Messages.message(locationLabel(loc, for: player)) ?? "",
                                  unitIds: sorted.compactMap(\.id)))
        }
        return UnitReport(forces: byNumber(forces), ref: ref, places: places)
    }
}
