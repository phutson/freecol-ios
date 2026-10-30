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

// The rest of Java's reports, as plain values made on the player's copy
// of the game.

/// A row of the exploration report (ReportExplorationPanel).
public struct RegionRow: Sendable, Equatable {
    public let name: String
    public let typeName: String
    public let discoveredIn: String
    public let discoveredBy: String
    public let value: Int
}

/// An event of the history report (ReportHistoryPanel).
public struct HistoryRow: Sendable, Equatable {
    public let turn: String
    public let text: String
}

/// A school and who could use it (ReportEducationPanel).
public struct SchoolRow: Sendable, Equatable {
    public let colonyId: String
    public let colonyName: String
    public let buildingName: String
    public let teacherIds: [String]
    /// The student, and the skill it would learn, in words.
    public let students: [(unitId: String, learning: String)]

    public static func == (a: SchoolRow, b: SchoolRow) -> Bool {
        a.colonyId == b.colonyId && a.buildingName == b.buildingName && a.teacherIds == b.teacherIds
            && a.students.map { $0.unitId + $0.learning } == b.students.map { $0.unitId + $0.learning }
    }
}

/// A European nation as the foreign affairs report shows it
/// (ReportForeignAffairPanel); the last three only with Jefferson.
public struct ForeignRow: Sendable, Equatable {
    public let country: String
    public let stance: String
    public let settlements: Int
    public let units: Int
    public let military: Int
    public let naval: Int
    public let gold: Int
    public let fathers: Int?
    public let tax: Int?
    public let sonsOfLiberty: Int?
}

/// A native nation (ReportIndianPanel).
public struct NativeNationRow: Sendable, Equatable {
    public let nation: String
    public let chieftain: String
    public let settlementType: String
    /// "<known> / <all>".
    public let numberOfSettlements: String
    public let tension: String
    public let settlements: [NativeSettlementRow]
}

public struct NativeSettlementRow: Sendable, Equatable {
    public let id: String
    public let name: String
    /// Who has a mission there.
    public let mission: String?
    public let alarm: String
    public let skill: String
    public let mostHated: String
    public let wanted: [String]
}

/// The trade report (ReportTradePanel): a column for each storable goods
/// type.
public struct TradeReport: Sendable, Equatable {
    public let goodsTypeIds: [String]
    public let sold: [Int]
    public let beforeTaxes: [Int]
    public let afterTaxes: [Int]
    public let cargo: [Int]
    public let total: [Int]
    public let delta: [Int]
    public let colonies: [TradeColonyRow]
}

public struct TradeColonyRow: Sendable, Equatable {
    public let id: String
    /// With a * if it has a custom house.
    public let name: String
    public let stock: [Int]
    public let production: [Int]
    /// By column: what is exported, and what is wrong with production.
    public let exports: [String?]
    public let warnings: [String?]
}

/// A colony's needs (ReportRequirementsPanel): "met", or what it lacks.
public struct RequirementsRow: Sendable, Equatable {
    public let colonyId: String
    public let colonyName: String
    public let lines: [String]
}

/// Production of chosen goods by colony (ReportProductionPanel).
public struct ProductionColumn: Sendable, Equatable {
    public let goodsTypeId: String
    public let goodsName: String
    /// The first levels of the buildings that make or improve it.
    public let buildingTypeIds: [String]
    public let buildingNames: [String]
}

public struct ProductionReport: Sendable, Equatable {
    public let columns: [ProductionColumn]
    public let colonies: [ProductionColonyRow]
}

public struct ProductionColonyRow: Sendable, Equatable {
    public let id: String
    public let name: String
    /// By column: the net production and the building at each level, if
    /// any.
    public let cells: [(net: Int, buildings: [String?])]

    public static func == (a: ProductionColonyRow, b: ProductionColonyRow) -> Bool {
        a.id == b.id && a.cells.map(\.net) == b.cells.map(\.net) && a.cells.map(\.buildings) == b.cells.map(\.buildings)
    }
}

/// The labour report (ReportLabourPanel, ReportLabourDetailPanel).
public struct LabourRow: Sendable, Equatable {
    public let typeId: String
    public let typeName: String
    public let count: Int
    /// Colonies first (a * if they could train it), then elsewhere.
    public let places: [(name: String, count: Int)]
    public let canTrain: Bool

    public static func == (a: LabourRow, b: LabourRow) -> Bool {
        a.typeId == b.typeId && a.count == b.count && a.canTrain == b.canTrain
            && a.places.map { "\($0.name)\($0.count)" } == b.places.map { "\($0.name)\($0.count)" }
    }
}

/// A colony in the colony report (ReportClassicColonyPanel).
public struct ColonyReportRow: Sendable, Equatable {
    public let id: String
    public let name: String
    public let building: String?
    public let colonistIds: [String]
    public let outsideIds: [String]
    public let goods: [ColonyGoodsRow]
    public let buildings: [String]
}

public struct ColonyGoodsRow: Sendable, Equatable {
    public let typeId: String
    public let net: Int
    public let stock: Int
    public let maximum: Int
}

/// Which units a unit report covers.
public enum UnitReportKind: Sendable {
    case military, naval, cargo
}

private func typeRoleSorted(_ units: [FreeColCore.Unit]) -> [FreeColCore.Unit] {
    units.sorted { a, b in
        let c = FreeColObject.compareIds(a.type, b.type)
        if c != 0 { return c < 0 }
        let ra = a.role?.roleIndex ?? 0, rb = b.role?.roleIndex ?? 0
        if ra != rb { return ra < rb }
        return FreeColObject.compareIds(a, b) < 0
    }
}

extension Colony {
    /// What is wrong with the production of goods (getProductionWarnings).
    func productionWarnings(_ goodsType: GoodsType) -> [StringTemplate] {
        let amount = goodsCount(goodsType)
        let production = netProduction(of: goodsType)
        var result: [StringTemplate] = []
        if goodsType.isStorable {
            if goodsType.limitIgnored {
                if goodsType.isFoodType {
                    let starve = starvationTurns
                    if starve == 0 {
                        result.append(StringTemplate.template("model.colony.starving").addName("%colony%", name))
                    } else if starve <= Colony.famineTurns {
                        result.append(StringTemplate.template("model.colony.famineFeared").addName("%colony%", name)
                            .addAmount("%number%", starve))
                    }
                }
            } else {
                let waste = amount + production - warehouseCapacity
                if !exportData(goodsType).exported && waste > 0 {
                    result.append(StringTemplate.template("model.building.warehouseSoonFull")
                        .addNamed("%goods%", goodsType).addName("%colony%", name).addAmount("%amount%", waste))
                }
            }
        }
        if let building = currentlyBuilding {
            for ag in building.requiredGoods where ag.type === goodsType && amount < ag.amount {
                result.append(StringTemplate.template("model.colony.buildableNeedsGoods").addName("%colony%", name)
                    .addNamed("%buildable%", building).addAmount("%amount%", ag.amount - amount)
                    .addNamed("%goodsType%", goodsType))
            }
        }
        func insufficient(_ info: ProductionInfo?, _ deficit: AbstractGoods?) -> StringTemplate? {
            guard let info, let deficit, let type = deficit.type, !info.consumptionDeficit.isEmpty else { return nil }
            let label = StringTemplate.label(", ")
            for ag in info.consumptionDeficit { _ = label.addStringTemplate(ag.label) }
            return StringTemplate.template("model.colony.insufficientProduction").addName("%colony%", name)
                .addNamed("%outputType%", type).addAmount("%outputAmount%", deficit.amount)
                .addStringTemplate("%consumptionDeficit%", label)
        }
        for wl in workLocations(producing: goodsType) {
            if let info = productionInfo(of: wl), let t = insufficient(info, wl.productionDeficit(goodsType)) {
                result.append(t)
            }
        }
        for wl in workLocations(consuming: goodsType) {
            guard let info = productionInfo(of: wl) else { continue }
            for ag in wl.outputs where ag.type?.isStorable ?? false {
                if let type = ag.type, let t = insufficient(info, wl.productionDeficit(type)) { result.append(t) }
            }
        }
        return result
    }
}

extension PlayerView {

    func explorationReport() -> [RegionRow] {
        let cal = game.specification?.turnCalendar ?? .standard
        let regions = (game.map?.regions ?? []).filter { $0.discoveredIn != nil }
        // By turn, then by value, most first.
        return regions.stableSorted { a, b in
            let ta = a.discoveredIn?.number ?? 0, tb = b.discoveredIn?.number ?? 0
            return ta != tb ? ta < tb : a.scoreValue > b.scoreValue
        }.map { r in
            RegionRow(name: r.name ?? "", typeName: r.type.map { Messages.message($0.nameKey) } ?? "",
                      discoveredIn: r.discoveredIn.flatMap { Messages.message($0.label(cal)) } ?? "",
                      discoveredBy: Messages.message(r.discoveredBy?.countryLabel) ?? "", value: r.scoreValue)
        }
    }

    func historyReport() -> [HistoryRow] {
        let cal = game.specification?.turnCalendar ?? .standard
        return player.history.map { e in
            HistoryRow(turn: e.turn.flatMap { Messages.message($0.label(cal)) } ?? "", text: Messages.message(e) ?? "")
        }
    }

    func educationReport() -> [SchoolRow] {
        var rows: [SchoolRow] = []
        for colony in player.colonyList {
            for building in colony.buildings where building.canTeach {
                let teachers = colony.unitList.filter { building.canAdd($0) }.stableSorted { $0.skillLevel < $1.skillLevel }
                var students: [(String, String)] = []
                for unit in colony.unitList {
                    guard let teacher = teachers.first(where: { unit.canBeStudent($0) }), let type = teacher.type,
                          let skill = unit.teachingType(type) else { continue }
                    students.append((unit.id ?? "", Messages.message(StringTemplate.template("report.education.tooltip")
                        .addNamed("%skill%", skill)) ?? ""))
                }
                rows.append(SchoolRow(colonyId: colony.id ?? "", colonyName: colony.name ?? "",
                                      buildingName: building.type.map { Messages.name($0) } ?? "",
                                      teacherIds: teachers.compactMap(\.id), students: students))
            }
        }
        return rows
    }

    /// `summary` gives the nation summary the server would send.
    func foreignReport(summary: (String) -> NationSummary?) -> [ForeignRow] {
        game.livePlayers.filter(\.isEuropean).compactMap { p in
            guard let id = p.id, let ns = summary(id) else { return nil }
            return ForeignRow(country: Messages.message(p.countryLabel) ?? "", stance: Messages.name(ns.stance),
                              settlements: ns.numberOfSettlements, units: ns.numberOfUnits,
                              military: ns.militaryStrength, naval: ns.navalStrength, gold: ns.gold,
                              fathers: ns.foundingFathers >= 0 ? ns.foundingFathers : nil,
                              tax: ns.tax >= 0 ? ns.tax : nil, sonsOfLiberty: ns.soL >= 0 ? ns.soL : nil)
        }
    }

    func nativesReport(summary: (String) -> NationSummary?) -> [NativeNationRow] {
        game.livePlayers.filter { $0.isIndian && player.hasContacted($0) }.map { opponent in
            let known = opponent.indianSettlementList
            let all = opponent.id.flatMap(summary).map { String($0.numberOfSettlements) } ?? "?"
            var ordered: [IndianSettlement] = []
            for s in known { if s.isCapital { ordered.insert(s, at: 0) } else { ordered.append(s) } }
            let capital = (opponent.nationType as? IndianNationType)?.capitalType
            return NativeNationRow(
                nation: Messages.message(opponent.nationLabel) ?? "",
                chieftain: Messages.message(opponent.name ?? ""),
                settlementType: capital.map { Messages.name($0.id) } ?? "",
                numberOfSettlements: "\(known.count) / \(all)",
                tension: Messages.message(StringTemplate.template("report.indian.tensionStance")
                    .addNamed("%tension%", opponent.tension(player)).addNamed("%stance%", opponent.stance(player))) ?? "",
                settlements: ordered.map { nativeRow($0) })
        }
    }

    private func nativeRow(_ s: IndianSettlement) -> NativeSettlementRow {
        let contacted = s.hasContacted(player), visited = s.hasVisited(player)
        var name = Messages.message(locationLabel(s, for: player)) ?? ""
        if (s.tile?.isExplored ?? false) && s.isCapital { name += "*" }
        if s.worthScouting(player) { name += "$" }
        let alarm = !player.hasContacted(s.owner) ? "model.indianSettlement.tension.wary"
            : !contacted ? "model.indianSettlement.tension.unknown"
            : s.alarm(player)?.nameKey ?? ""
        let n = visited ? s.wantedGoodsCount : 1
        let wanted = (0..<n).map { i -> String in
            guard visited else { return "" }
            guard let gt = s.wantedGoods(i) else { return Messages.message("model.indianSettlement.wantedGoodsNone") }
            return Messages.name(gt) + (player.lastSaleString(s, gt).map { " " + $0 } ?? "")
        }
        return NativeSettlementRow(
            id: s.id ?? "", name: name, mission: Messages.message(s.missionary?.label(.national)),
            alarm: Messages.message(alarm), skill: Messages.message(s.learnableSkillLabel(visited)) ?? "",
            mostHated: Messages.message(s.mostHatedLabel(contacted)) ?? "", wanted: wanted)
    }

    func tradeReport() -> TradeReport {
        let storable = game.specification?.storableGoodsTypeList ?? []
        var cargo: [ObjectIdentifier: Int] = [:], total: [ObjectIdentifier: Int] = [:], delta: [ObjectIdentifier: Int] = [:]
        for u in player.units where u.isCarrier {
            for g in u.compactGoodsList {
                guard let t = g.type else { continue }
                cargo[ObjectIdentifier(t), default: 0] += g.amount
                total[ObjectIdentifier(t), default: 0] += g.amount
            }
        }
        var rows: [TradeColonyRow] = []
        for c in player.colonyList {
            for gt in game.specification?.goodsTypeList ?? [] {
                delta[ObjectIdentifier(gt), default: 0] += c.netProduction(of: gt)
            }
            for g in c.compactGoodsList {
                if let t = g.type { total[ObjectIdentifier(t), default: 0] += g.amount }
            }
            rows.append(TradeColonyRow(
                id: c.id ?? "", name: (c.name ?? "") + (c.hasAbility(Ability.export) ? "*" : ""),
                stock: storable.map { c.goodsCount($0) }, production: storable.map { c.netProduction(of: $0) },
                exports: storable.map { gt in
                    let ed = c.exportData(gt)
                    return ed.exported ? Messages.message(StringTemplate.template("report.trade.export")
                        .addNamed("%goods%", gt).addAmount("%amount%", ed.exportLevel)) : nil
                },
                warnings: storable.map { gt in
                    let w = c.productionWarnings(gt)
                    return w.isEmpty ? nil : w.map { Messages.message($0) ?? "" }.joined(separator: " ")
                }))
        }
        func column(_ d: [ObjectIdentifier: Int]) -> [Int] { storable.map { d[ObjectIdentifier($0)] ?? 0 } }
        return TradeReport(goodsTypeIds: storable.compactMap(\.id), sold: storable.map { player.sales($0) },
                           beforeTaxes: storable.map { player.incomeBeforeTaxes($0) },
                           afterTaxes: storable.map { player.incomeAfterTaxes($0) },
                           cargo: column(cargo), total: column(total), delta: column(delta), colonies: rows)
    }

    func requirementsReport() -> [RequirementsRow] {
        let colonies = player.colonyList
        return colonies.map { RequirementsRow(colonyId: $0.id ?? "", colonyName: $0.name ?? "",
                                              lines: requirements($0, colonies)) }
    }

    private func requirements(_ colony: Colony, _ colonies: [Colony]) -> [String] {
        guard let spec = game.specification else { return [] }
        func count(_ c: Colony, _ t: UnitType) -> Int { c.unitList.filter { $0.type === t }.count }
        var lines: [String] = []
        var missing = Set<ObjectIdentifier>(), bad = Set<ObjectIdentifier>(), shortGoods = Set<ObjectIdentifier>()

        func expertWarning(_ goods: GoodsType, _ expert: UnitType) {
            lines.append(Messages.message(StringTemplate.template("report.requirements.noExpert")
                .addName("%colony%", colony.name).addName("%goods%", goods).addName("%unit%", expert)) ?? "")
            var misused: [Colony] = [], several: [Colony] = [], train: [Colony] = []
            for c in colonies {
                for u in c.unitList where u.type?.expertProduction === goods && u.skillLevel > 0 {
                    if let b = u.location as? Building {
                        if !b.canProduce(goods, u.type) { misused.append(c) }
                    } else if goods !== u.workType {
                        misused.append(c)
                    }
                }
                if count(c, expert) > 1 { several.append(c) }
                if c.unitList.contains(where: { $0.type === expert && c.canTrain($0.type) }) { train.append(c) }
            }
            func names(_ l: [Colony]) -> String { l.map { $0.name ?? "" }.joined(separator: ", ") }
            if !misused.isEmpty {
                lines.append((Messages.message(StringTemplate.template("report.requirements.misusedExperts")
                    .addName("%unit%", expert).add("%work%", goods.workingAsKey)) ?? "") + " " + names(misused))
            }
            if !several.isEmpty {
                lines.append((Messages.message(StringTemplate.template("report.requirements.severalExperts")
                    .addName("%unit%", expert)) ?? "") + " " + names(several))
            }
            if !train.isEmpty {
                lines.append((Messages.message(StringTemplate.template("report.requirements.canTrainExperts")
                    .addName("%unit%", expert)) ?? "") + " " + names(train))
            }
        }

        for u in colony.unitList where u.skillLevel > 0 {
            guard let better = colony.betterExpert(u), let t = u.type, !bad.contains(ObjectIdentifier(t)),
                  let eg = u.workType, let ng = better.workType, let bt = better.type else { continue }
            lines.append(Messages.message(StringTemplate.template("report.requirements.badAssignment")
                .addName("%colony%", colony.name).addName("%expert%", Messages.name(t))
                .addName("%expertWork%", Messages.message(eg.workingAsKey))
                .addName("%nonExpert%", Messages.name(bt))
                .addName("%nonExpertWork%", Messages.message(ng.workingAsKey))) ?? "")
            bad.insert(ObjectIdentifier(t))
        }
        for ct in colony.colonyTiles {
            for u in ct.unitList {
                guard let work = u.workType, let expert = spec.expert(producing: work) else { continue }
                if count(colony, expert) == 0 && missing.insert(ObjectIdentifier(expert)).inserted {
                    expertWarning(work, expert)
                }
            }
        }
        for b in colony.buildings {
            for output in b.outputs {
                guard let goods = output.type else { continue }
                if let expert = spec.expert(producing: goods), !b.unitList.isEmpty,
                   !missing.contains(ObjectIdentifier(expert)), count(colony, expert) == 0 {
                    if !colony.goodsUseful(goods) { continue }
                    expertWarning(goods, expert)
                    missing.insert(ObjectIdentifier(expert))
                }
                if let info = colony.productionInfo(of: b), !info.atMaximumProduction,
                   shortGoods.insert(ObjectIdentifier(goods)).inserted {
                    for input in b.inputs.compactMap(\.type) {
                        lines.append(Messages.message(StringTemplate.template("report.requirements.missingGoods")
                            .addName("%colony%", colony.name).addNamed("%goods%", goods)
                            .addNamed("%input%", input)) ?? "")
                        // As in Java, each colony is shown with this
                        // colony's surplus.
                        let amount = colony.adjustedNetProduction(of: input)
                        if amount > 0 {
                            lines.append((Messages.message(StringTemplate.template("report.requirements.surplus")
                                .addNamed("%goods%", input)) ?? "") + " "
                                + colonies.map { "\($0.name ?? "") (\(amount))" }.joined(separator: ", "))
                        }
                    }
                }
            }
        }
        let suggestions = colony.tileImprovementSuggestions
        for s in suggestions {
            let key = s.tileImprovementType.map { "report.requirements.tile." + ($0.suffix ?? "") }
                ?? "report.requirements.exploreTile"
            if Messages.containsKey(key) {
                lines.append(Messages.message(StringTemplate.template(key)
                    .addStringTemplate("%location%", s.tile.colonyTileLocationLabel(colony))) ?? "")
            }
        }
        if suggestions.isEmpty && missing.isEmpty && bad.isEmpty && shortGoods.isEmpty {
            lines.append(Messages.message("report.requirements.met"))
        }
        return lines
    }

    /// The goods the production report can be asked about: not farmed.
    var productionGoods: [GoodsType] {
        (game.specification?.goodsTypeList ?? []).filter { !$0.isFarmed }
    }

    func productionReport(_ goodsTypeIds: [String]) -> ProductionReport {
        guard let spec = game.specification else { return ProductionReport(columns: [], colonies: []) }
        let selected = goodsTypeIds.compactMap { spec.getGoodsType($0) }
        // Java keeps these in a hash set; here they are in the rules' order.
        let levels: [[BuildingType]] = selected.map { gt in
            var seen = Set<ObjectIdentifier>(), out: [BuildingType] = []
            for bt in spec.buildingTypeList where gt === bt.producedGoodsType || bt.hasModifier(gt.id) {
                let first = bt.firstLevel
                if seen.insert(ObjectIdentifier(first)).inserted { out.append(first) }
            }
            return out
        }
        let columns = zip(selected, levels).map { gt, l in
            ProductionColumn(goodsTypeId: gt.id ?? "", goodsName: Messages.name(gt), buildingTypeIds: l.compactMap(\.id),
                             buildingNames: l.map { Messages.name($0) })
        }
        let rows = player.colonyList.map { c in
            ProductionColonyRow(id: c.id ?? "", name: c.name ?? "", cells: zip(selected, levels).map { gt, l in
                (c.netProduction(of: gt), l.map { bt in
                    c.building(bt).flatMap { $0.type }.map { Messages.name($0) }
                })
            })
        }
        return ProductionReport(columns: columns, colonies: rows)
    }

    func labourReport() -> [LabourRow] {
        guard let spec = game.specification else { return [] }
        var counts: [ObjectIdentifier: Int] = [:]
        var at: [ObjectIdentifier: [(loc: any Location, count: Int)]] = [:]
        for u in player.units {
            guard let t = u.type else { continue }
            counts[ObjectIdentifier(t), default: 0] += 1
            guard var loc = u.location else { continue }
            if let s = loc.settlement {
                loc = s
            } else if u.isInEurope, let e = player.europe {
                loc = e
            } else if let tile = loc.tile {
                loc = tile
            }
            var list = at[ObjectIdentifier(t)] ?? []
            if let i = list.firstIndex(where: { $0.loc === loc }) { list[i].count += 1 } else { list.append((loc, 1)) }
            at[ObjectIdentifier(t)] = list
        }
        return spec.unitTypeList.filter { $0.isPerson && $0.isAvailableTo(player) }.map { t in
            let here = at[ObjectIdentifier(t)] ?? []
            var places: [(String, Int)] = []
            var canTrain = false
            for c in player.colonyList {
                guard let e = here.first(where: { $0.loc === c }) else { continue }
                let trains = c.canTrain(t)
                canTrain = canTrain || trains
                places.append(((c.name ?? "") + (trains ? "*" : ""), e.count))
            }
            // Java's map has no useful order; here by identifier.
            for e in here.filter({ !($0.loc is Colony) }).sorted(by: { ($0.loc.id ?? "") < ($1.loc.id ?? "") }) {
                places.append((Messages.message(locationLabel(e.loc)) ?? "", e.count))
            }
            return LabourRow(typeId: t.id ?? "", typeName: Messages.name(t), count: counts[ObjectIdentifier(t)] ?? 0,
                             places: places, canTrain: canTrain)
        }
    }

    func colonyReport() -> [ColonyReportRow] {
        guard let spec = game.specification else { return [] }
        let goods = spec.goodsTypeList.stableSorted { GoodsType.compare($0, $1) < 0 }
        return player.colonyList.map { c in
            let rows = goods.compactMap { gt -> ColonyGoodsRow? in
                let net = c.netProduction(of: gt), stock = c.goodsCount(gt)
                guard net != 0 || stock > 0 else { return nil }
                let maximum = c.workLocations(producing: gt).reduce(0) { $0 + $1.maximumProduction(of: gt) }
                return ColonyGoodsRow(typeId: gt.id ?? "", net: net, stock: stock, maximum: maximum)
            }
            let buildings = c.buildings.filter { !($0.type?.isAutomaticBuild ?? false) }.stableSorted {
                ($0.type?.index ?? 0) < ($1.type?.index ?? 0)
            }
            return ColonyReportRow(
                id: c.id ?? "", name: c.name ?? "", building: c.currentlyBuilding.map { Messages.name($0) },
                colonistIds: typeRoleSorted(c.unitList).compactMap(\.id),
                outsideIds: typeRoleSorted(c.tile?.unitList ?? []).compactMap(\.id),
                goods: rows, buildings: buildings.compactMap { $0.type.map { Messages.name($0) } })
        }
    }
}
