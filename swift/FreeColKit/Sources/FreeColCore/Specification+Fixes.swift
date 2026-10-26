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
import FreeColUtil
import FreeColXML

/// Where a specification finds the files it refers to while loading:
/// the rule sets it extends and the compatibility fragments some fixes
/// read.  FreeColIO provides one for FreeCol's data directory.
public protocol RulesSource {
    /// The specification.xml of a rule set, by id ("classic").
    func rulesData(_ id: String) throws -> Data?
    /// A compatibility file from the base data directory.
    func compatibilityData(_ fileName: String) throws -> Data?
}

/// How European national advantages are chosen (NationOptions.Advantages).
public enum Advantages: JavaEnum {
    case none, fixed, selectable
    public var javaName: String {
        switch self { case .none: "NONE"; case .fixed: "FIXED"; case .selectable: "SELECTABLE" }
    }
}

extension Specification {

    // MARK: Loading

    /// Load a rule set the way FreeCol.loadSpecification does: read it
    /// (and the rule sets it extends), prepare it with its own difficulty
    /// and clean it, as the Specification constructor does, then prepare
    /// it again with the advantages and difficulty chosen.
    ///
    /// - Parameters:
    ///   - id: The rule set id, such as "freecol".
    ///   - source: Where to find rule set and compatibility files.
    ///   - advantages: How national advantages are chosen, if known.
    ///   - difficulty: The difficulty level id, such as
    ///     "model.difficulty.medium".
    public static func loadRules(_ id: String, from source: RulesSource,
                                 advantages: Advantages? = nil,
                                 difficulty: String?) throws -> Specification {
        guard let data = try source.rulesData(id) else {
            throw FreeColXMLError("No such rules: \(id)")
        }
        let spec = Specification()
        spec.source = source
        try spec.load(data)
        try spec.prepare(advantages: nil, difficulty: spec.difficultyLevel)
        spec.clean()
        spec.isInitialized = true
        try spec.prepare(advantages: advantages, difficulty: difficulty)
        return spec
    }

    /// Read mods into the specification, then clean it once (Java's
    /// loadMods).  A mod without rules (nil data) counts as loaded.
    ///
    /// - Returns: Whether any mod was loaded.
    @discardableResult
    public func loadMods(_ mods: [Data?]) throws -> Bool {
        isInitialized = false
        var loaded = false
        for mod in mods {
            if let mod { try load(mod) }
            loaded = true
        }
        if loaded { clean() }
        isInitialized = true
        return loaded
    }

    /// Apply the compatibility fixes, the advantages and a difficulty
    /// level (Java's prepare).
    public func prepare(advantages: Advantages?, difficulty: String?) throws {
        _ = try applyFixes()
        if advantages == Advantages.none {
            for n in europeanNations { n.type = defaultNationType }
        }
        if let level = difficultyOptionGroup(difficulty) {
            optionGroup("difficultyLevels")?.add(level)
            allOptionGroups.put(level.id ?? "", level)
            applyDifficultyLevel(level)
        }
    }

    // MARK: Fixes (Java's applyFixes)

    /// Repair specifications from older versions of FreeCol.  Some of
    /// these always run, and some are not idempotent (the customs house
    /// fix adds another ability whenever the existing one is false), as
    /// in Java.
    func applyFixes() throws -> Bool {
        var ret = false
        ret = fixDifficultyOptions() || ret
        ret = try fixGameOptions() || ret
        ret = fixOrphanOptions() || ret
        ret = try fixRoles() || ret
        ret = try fixUnitChanges() || ret
        ret = try fixSpec() || ret
        return ret
    }

    /// Java's compareVersion: the version against another "major.minor",
    /// 0 when the specification has no version.
    private func compareVersion(_ other: String) throws -> Int {
        guard let version else { return 0 }
        let sv = version.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let so = other.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        if sv.count == 2, so.count == 2,
           let a0 = JavaString.parseInt(sv[0]), let b0 = JavaString.parseInt(so[0]),
           let a1 = JavaString.parseInt(sv[1]), let b1 = JavaString.parseInt(so[1]) {
            if a0 != b0 { return a0 < b0 ? -1 : 1 }
            return a1 < b1 ? -1 : a1 > b1 ? 1 : 0
        }
        throw FreeColXMLError("Bad version: \(other)")
    }

    /// Drop options not reachable from the game, map generator or
    /// difficulty groups.
    private func fixOrphanOptions() -> Bool {
        var orphanOptions = allOptions.values
        var orphanGroups = allOptionGroups.values.map { $0 as AbstractOption }
        func drop(_ o: AbstractOption?, _ all: inout [AbstractOption]) {
            guard let o else { return }
            all.removeAll { $0 === o }
            if let g = o as? OptionGroup { for op in g.options { drop(op, &all) } }
        }
        for id in ["gameOptions", "mapGeneratorOptions", "difficultyLevels"] {
            drop(allOptionGroups[id], &orphanOptions)
            drop(allOptionGroups[id], &orphanGroups)
        }
        for ao in orphanOptions {
            var values = allOptions.values
            drop(ao, &values)
            for e in allOptions.entries where !values.contains(where: { $0 === e.value }) {
                allOptions.removeValue(forKey: e.key)
            }
            if ao is OptionGroup { allOptionGroups.removeValue(forKey: ao.id ?? "") }
        }
        for ao in orphanGroups { allOptionGroups.removeValue(forKey: ao.id ?? "") }
        return !orphanOptions.isEmpty || !orphanGroups.isEmpty
    }

    /// @compat 0.11.0: very old rule sets had no roles.
    private func fixRoles() throws -> Bool {
        if !rolesList.isEmpty { return false }
        if try compareVersion("0.85") > 0 { return false }
        guard let data = try source?.compatibilityData("roles-compat.xml") else { return false }
        try load(data)
        return true
    }

    /// @compat 0.11.6: unit changes moved into unit-change-types.  The
    /// enter-colony change from the convertUpgrade mod is kept.
    private func fixUnitChanges() throws -> Bool {
        if try compareVersion("0.116") > 0 { return false }
        let enter = unitChangeTypeList.first { $0.id == UnitChangeType.enterColony }
        guard let data = try source?.compatibilityData("unit-change-types-compat.xml") else { return false }
        try load(data)
        if let enter { unitChangeTypeList.append(enter) }
        return true
    }

    private func fixSpec() throws -> Bool {
        var ret = false
        // @compat 0.10.x/0.11.x: the unknown enemy nation.
        let ue = try findType(Nation.unknownNationId, Nation.self)
        ue.type = getNationType("model.nationType.default")
        if !nations.contains(where: { $0 === ue }) {
            nations.append(ue)
            ret = true
        }
        for nation in nations where nation.rgb == nil {
            nation.rgb = Specification.defaultColors[nation.id ?? ""]
            ret = true
        }
        let coronado = getFoundingFather("model.foundingFather.franciscoDeCoronado")
        if id == "freecol", let coronado, !coronado.hasAbility(Ability.seeAllColonies) {
            coronado.addAbility(Ability(Ability.seeAllColonies, source: coronado, value: true))
            ret = true
        }
        // REF roles: soldier became infantry, dragoon became cavalry.
        for level in difficultyLevels {
            let monarch = level.option(GameOptions.difficultyMonarch)
            let holder = (monarch as? OptionGroup) ?? level
            guard let refSize = holder.option(GameOptions.refForce) as? UnitListOption else { continue }
            for au in refSize.optionValues {
                switch au.roleId {
                case "DEFAULT": au.roleId = Specification.defaultRoleId; ret = true
                case "model.role.soldier", "SOLDIER": au.roleId = "model.role.infantry"; ret = true
                case "model.role.dragoon", "DRAGOON": au.roleId = "model.role.cavalry"; ret = true
                default: break
                }
            }
        }
        // Other unit lists: old role names.
        var todo: [AbstractOption] = difficultyLevels
        while !todo.isEmpty {
            let o = todo.removeFirst()
            if let g = o as? OptionGroup {
                todo += g.options
            } else if let ulo = o as? UnitListOption {
                for au in ulo.optionValues {
                    guard let roleId = au.roleId else {
                        au.roleId = Specification.defaultRoleId
                        ret = true
                        continue
                    }
                    if JavaString.startsWith(roleId, "model.role.") { continue }
                    switch roleId {
                    case "DRAGOON": au.roleId = "model.role.dragoon"
                    case "MISSIONARY": au.roleId = "model.role.missionary"
                    case "PIONEER": au.roleId = "model.role.pioneer"
                    case "SCOUT": au.roleId = "model.role.scout"
                    case "SOLDIER": au.roleId = "model.role.soldier"
                    default: au.roleId = Specification.defaultRoleId
                    }
                    ret = true
                }
            }
        }
        for goodsId in ["model.goods.horses", "model.goods.muskets"] {
            if let gt = getGoodsType(goodsId), !gt.isMilitary {
                gt.setMilitary()
                ret = true
            }
        }
        // @compat 0.11.0: Bolivar became a SoL modifier.
        if let bolivar = getFoundingFather("model.foundingFather.simonBolivar") {
            var bolivarAdd = false
            if !bolivar.events.isEmpty {
                bolivar.clearEvents()
                bolivarAdd = true
            } else if bolivar.hasModifier(Modifier.liberty) {
                bolivar.removeModifiers(Modifier.liberty)
                bolivarAdd = true
            }
            if bolivarAdd {
                bolivar.addModifier(Modifier(Modifier.sol, 20, .additive, source: bolivar, index: 0))
                ret = true
            }
        }
        // The coastal-only ability of the custom house.  hasAbility is
        // false when the ability is false, so this adds another one
        // every time, as Java does.
        if let customs = getBuildingType("model.building.customHouse"),
           !customs.hasAbility(Ability.coastalOnly) {
            customs.addAbility(Ability(Ability.coastalOnly, source: nil, value: false))
            ret = true
        }
        // @compat 0.11.3: the cargo penalty.
        if modifiers(Modifier.cargoPenalty).isEmpty {
            addModifier(Modifier(Modifier.cargoPenalty, -12.5, .percentage,
                                 source: getType(SourceId.cargoPenalty),
                                 index: Modifier.generalCombatIndex))
            ret = true
        }
        if let limit = getEvent("model.event.declareIndependence")?
            .limit("model.limit.independence.coastalColonies") {
            limit.operator = .ge
            limit.rightHandSide.value = 1
            ret = true
        }
        // @compat 0.11.5
        if let hardyPioneer = getUnitType("model.unit.hardyPioneer"),
           hardyPioneer.modifiers(Modifier.tileTypeChangeProduction).isEmpty {
            let m = Modifier(Modifier.tileTypeChangeProduction, 2, .multiplicative)
            let scope = Scope()
            scope.type = "model.goods.lumber"
            m.addScope(scope)
            hardyPioneer.addModifier(m)
            ret = true
        }
        if let coronado, !coronado.hasModifier(Modifier.exposedTilesRadius) {
            coronado.addModifier(Modifier(Modifier.exposedTilesRadius, 3, .additive, source: coronado, index: 0))
            ret = true
        }
        // @compat 0.11.6: plunder types gained ids.
        for nt in indianNationTypes {
            for st in nt.settlementTypes {
                for pt in st.plunderTypes where pt.id == nil {
                    let extra = pt.scopes.contains { $0.abilityId == "model.ability.plunderNatives" }
                    pt.id = "plunder.\(nt.suffix ?? "null")" + (st.isCapital ? ".capital" : "")
                        + (extra ? ".extra" : "")
                    ret = true
                }
            }
        }
        if let casas = getFoundingFather("model.foundingFather.bartolomeDeLasCasas"),
           !casas.hasAbility(Ability.upgradeConvert) {
            let uc = Ability(Ability.upgradeConvert, source: casas, value: true)
            addAbility(uc)
            casas.addAbility(uc)
            ret = true
        }
        if let mow = getUnitType("model.unit.manOWar") {
            if mow.mercenaryPrice < 0 {
                mow.mercenaryPrice = 10000
                ret = true
            }
            let maidId = "model.ability.independenceDeclared"
            if mow.requiresAbility(maidId) {
                mow.removeRequiredAbility(maidId)
                mow.addRequiredAbility(Ability.independentNation, true)
                ret = true
            }
        }
        for ut in unitTypes(withAnyAbility: Ability.refUnit)
            where !ut.containsAbilityKey(Ability.canBeSurrendered) {
            ut.addAbility(Ability(Ability.canBeSurrendered, source: nil,
                                  value: ut.id == "model.unit.artillery"))
            ret = true
        }
        return ret
    }

    // MARK: Difficulty option fixes

    private func fixDifficultyOptions() -> Bool {
        var ret = false
        // @compat 0.10.x/0.11.x: options moved into groups.
        ret = checkDifficultyOptionGroup(GameOptions.difficultyImmigration, [
            GameOptions.crossesIncrement, GameOptions.recruitPriceIncrease,
            GameOptions.lowerCapIncrease, GameOptions.priceIncrease + ".artillery",
            GameOptions.priceIncreasePerType, GameOptions.expertStartingUnits,
            GameOptions.immigrants]) || ret
        ret = checkDifficultyOptionGroup(GameOptions.difficultyNatives, [
            GameOptions.landPriceFactor, GameOptions.nativeConvertProbability,
            GameOptions.burnProbability, GameOptions.nativeDemands,
            GameOptions.rumourDifficulty, GameOptions.shipTradePenalty,
            GameOptions.buildOnNativeLand, GameOptions.settlementNumber]) || ret
        ret = checkDifficultyOptionGroup(GameOptions.difficultyMonarch, [
            GameOptions.monarchMeddling, GameOptions.taxAdjustment,
            GameOptions.mercenaryPrice, GameOptions.maximumTax,
            GameOptions.monarchSupport, GameOptions.treasureTransportFee,
            GameOptions.refForce, GameOptions.interventionBells,
            GameOptions.interventionTurns, GameOptions.interventionForce,
            GameOptions.mercenaryForce]) || ret
        ret = checkDifficultyOptionGroup(GameOptions.difficultyGovernment, [
            GameOptions.badGovernmentLimit, GameOptions.veryBadGovernmentLimit,
            GameOptions.goodGovernmentLimit, GameOptions.veryGoodGovernmentLimit]) || ret
        ret = checkDifficultyOptionGroup(GameOptions.difficultyOther, [
            GameOptions.startingMoney, GameOptions.foundingFatherFactor,
            GameOptions.arrearsFactor, GameOptions.unitsThatUseNoBells,
            GameOptions.tileProduction]) || ret
        ret = checkDifficultyOptionGroup(GameOptions.difficultyCheat, [
            GameOptions.liftBoycottCheat, GameOptions.equipScoutCheat,
            GameOptions.landUnitCheat, GameOptions.offensiveNavalUnitCheat,
            GameOptions.transportNavalUnitCheat]) || ret

        func units(_ listId: String, _ group: String,
                   _ members: [(String, String, String?, Int)]) {
            guard let ulo = checkDifficultyUnitListOption(listId, group) else { return }
            for (suffix, type, role, number) in members {
                let op = AbstractUnitOption(id: suffix.isEmpty ? listId : "\(listId).\(suffix)",
                                            specification: self)
                op.setValue(AbstractUnit(id: type, roleId: role, number: number))
                ulo.add(op)
            }
            ret = true
        }
        let defaultRole = Specification.defaultRoleId
        units(GameOptions.refForce, GameOptions.difficultyMonarch, [
            ("regulars", "model.unit.kingsRegular", "model.role.infantry", 31),
            ("dragoons", "model.unit.kingsRegular", "model.role.cavalry", 15),
            ("artillery", "model.unit.artillery", defaultRole, 14),
            ("menOfWar", "model.unit.manOWar", defaultRole, 8)])
        units(GameOptions.immigrants, GameOptions.difficultyImmigration, [
            ("1", "model.unit.masterCarpenter", defaultRole, 1)])
        ret = checkDifficultyIntegerOption(GameOptions.interventionBells, GameOptions.difficultyMonarch, 5000) || ret
        ret = checkDifficultyIntegerOption(GameOptions.interventionTurns, GameOptions.difficultyMonarch, 52) || ret
        units(GameOptions.interventionForce, GameOptions.difficultyMonarch, [
            ("regulars", "model.unit.colonialRegular", "model.role.soldier", 2),
            ("dragoons", "model.unit.colonialRegular", "model.role.dragoon", 2),
            ("artillery", "model.unit.artillery", defaultRole, 2),
            ("menOfWar", "model.unit.manOWar", defaultRole, 2)])
        units(GameOptions.mercenaryForce, GameOptions.difficultyMonarch, [
            ("regulars", "model.unit.veteranSoldier", "model.role.soldier", 2),
            ("dragoons", "model.unit.veteranSoldier", "model.role.dragoon", 2),
            ("artillery", "model.unit.artillery", defaultRole, 2),
            ("menOfWar", "model.unit.manOWar", defaultRole, 2)])
        ret = checkDifficultyIntegerOption(GameOptions.goodGovernmentLimit, GameOptions.difficultyGovernment, 50) || ret
        ret = checkDifficultyIntegerOption(GameOptions.veryGoodGovernmentLimit, GameOptions.difficultyGovernment, 100) || ret
        ret = checkDifficultyIntegerOption(GameOptions.liftBoycottCheat, GameOptions.difficultyCheat, 10) || ret
        ret = checkDifficultyIntegerOption(GameOptions.equipScoutCheat, GameOptions.difficultyCheat, 10) || ret
        ret = checkDifficultyIntegerOption(GameOptions.landUnitCheat, GameOptions.difficultyCheat, 10) || ret
        ret = checkDifficultyIntegerOption(GameOptions.offensiveNavalUnitCheat, GameOptions.difficultyCheat, 10) || ret
        ret = checkDifficultyIntegerOption(GameOptions.transportNavalUnitCheat, GameOptions.difficultyCheat, 10) || ret
        // @compat 0.11.0
        ret = checkDifficultyIntegerOption(GameOptions.destroySettlementScore, GameOptions.difficultyNatives, -5) || ret
        ret = checkDifficultyPercentageOption(GameOptions.badRumour, GameOptions.difficultyOther, 23) || ret
        ret = checkDifficultyPercentageOption(GameOptions.goodRumour, GameOptions.difficultyOther, 48) || ret
        ret = checkDifficultyIntegerOption(GameOptions.offensiveLandUnitCheat, GameOptions.difficultyCheat, 4) || ret
        ret = checkDifficultyIntegerOption(GameOptions.equipPioneerCheat, GameOptions.difficultyCheat, 10) || ret
        // @compat 0.11.3
        units(GameOptions.warSupportForce, GameOptions.difficultyMonarch, [
            ("", "model.unit.veteranSoldier", "model.role.soldier", 4)])
        ret = checkDifficultyIntegerOption(GameOptions.warSupportGold, GameOptions.difficultyMonarch, 1500) || ret
        // @compat 1.0.0
        ret = checkDifficultyIntegerOption(GameOptions.tradeProfitMultiplierCheat, GameOptions.difficultyCheat, 10) || ret
        ret = checkDifficultyIntegerOption(GameOptions.tradeProfitMultiplierCheatTurns, GameOptions.difficultyCheat, 200) || ret
        // Java then only logs groups nested too deeply.
        return ret
    }

    /// The direct member of a level that is a group with an id.
    private func levelGroup(_ level: OptionGroup, _ id: String) -> OptionGroup? {
        level.options.first { $0.id == id && $0 is OptionGroup } as? OptionGroup
    }

    /// The direct member of a level that is a non-group option with an id.
    private func levelOption(_ level: OptionGroup, _ id: String) -> AbstractOption? {
        level.options.first { $0.id == id && !($0 is OptionGroup) }
    }

    private func checkDifficultyOptionGroup(_ gr: String, _ ids: [String]) -> Bool {
        var ret = false
        for level in difficultyLevels {
            var og = levelGroup(level, gr)
            if og == nil {
                level.remove(gr)
                let created = OptionGroup(id: gr, specification: self)
                level.add(created)
                created.group = level.id ?? ""
                og = created
                ret = true
            }
            for id in ids {
                if let op = levelOption(level, id) {
                    level.remove(op.id ?? "")
                    op.group = og!.id ?? ""
                    og!.add(op)
                    ret = true
                }
            }
        }
        return ret
    }

    private func checkDifficultyIntegerOption(_ id: String, _ gr: String, _ defaultValue: Int) -> Bool {
        checkDifficultyValueOption(id, gr) { $0 is IntegerOption } make: {
            let op = IntegerOption(id: id, specification: self)
            op.setValue(defaultValue)
            return op
        }
    }

    private func checkDifficultyPercentageOption(_ id: String, _ gr: String, _ defaultValue: Int) -> Bool {
        checkDifficultyValueOption(id, gr) { $0 is PercentageOption } make: {
            let op = PercentageOption(id: id, specification: self)
            op.setValue(defaultValue)
            return op
        }
    }

    /// The shared shape of Java's checkDifficultyIntegerOption and
    /// checkDifficultyPercentageOption.
    private func checkDifficultyValueOption(_ id: String, _ gr: String,
                                            isRightKind: (AbstractOption) -> Bool,
                                            make: () -> AbstractOption) -> Bool {
        var ret = false
        for level in difficultyLevels {
            guard let og = levelGroup(level, gr) else { continue }
            if var op = levelOption(level, id) {
                level.remove(op.id ?? "")
                if !isRightKind(op) { op = make() }
                op.group = gr
                og.add(op)
            } else {
                let existing = og.options.first { $0.id == id }
                if let existing, isRightKind(existing) { continue }
                if existing != nil { og.remove(id) }
                let op = make()
                op.group = gr
                og.add(op)
            }
            ret = true
        }
        return ret
    }

    private func checkDifficultyUnitListOption(_ id: String, _ gr: String) -> UnitListOption? {
        var ulo: UnitListOption?
        for level in difficultyLevels {
            guard let og = levelGroup(level, gr) else { continue }
            if let op = levelOption(level, id) {
                level.remove(op.id ?? "")
                op.group = og.id ?? ""
                og.add(op)
            } else {
                let existing = og.options.first { $0.id == id }
                if existing is UnitListOption { continue }
                if existing != nil { og.remove(id) }
                // Java shares one new list among the levels missing it.
                if ulo == nil { ulo = UnitListOption(id: id, specification: self) }
                og.add(ulo!)
            }
        }
        return ulo
    }

    // MARK: Game option fixes

    private func fixGameOptions() throws -> Bool {
        var ret = false
        func bool(_ id: String, _ gr: String, _ v: Bool) {
            ret = checkOp(id, gr) { let o = BooleanOption(id: id, specification: self); o.setValue(v); return o } || ret
        }
        func pct(_ id: String, _ gr: String, _ v: Int) {
            ret = checkOp(id, gr) { let o = PercentageOption(id: id, specification: self); o.setValue(v); return o } || ret
        }
        func int(_ id: String, _ gr: String, _ v: Int) {
            ret = checkOp(id, gr) { let o = IntegerOption(id: id, specification: self); o.setValue(v); return o } || ret
        }
        let colony = GameOptions.gameoptionsColony, map = GameOptions.gameoptionsMap
        let years = GameOptions.gameoptionsYears
        // @compat 0.10.5
        bool(GameOptions.enableUpkeep, colony, false)
        pct(GameOptions.naturalDisasters, colony, 0)
        pct(GameOptions.giftProbability, map, 5)
        pct(GameOptions.demandProbability, map, 10)
        bool(GameOptions.emptyTraders, map, false)
        // @compat 0.10.7
        bool(GameOptions.onlyNaturalImprovements, colony, true)
        pct(GameOptions.peaceProbability, map, 90)
        int(GameOptions.initialImmigration, map, 15)
        int(GameOptions.europeanUnitImmigrationPenalty, map, -4)
        int(GameOptions.playerImmigrationBonus, map, 2)
        bool(GameOptions.foundColonyDuringRebellion, colony, true)
        // @compat 0.11.0
        bool(GameOptions.bellAccumulationCapped, colony, false)
        bool(GameOptions.captureUnitsUnderRepair, colony, false)
        bool(GameOptions.payForBuilding, colony, true)
        bool(GameOptions.clearHammersOnConstructionSwitch, colony, false)
        bool(GameOptions.customsOnCoast, colony, false)
        bool(GameOptions.equipEuropeanRecruits, colony, true)
        // @compat 0.11.3
        int(GameOptions.missionInfluence, map, -10)
        int(GameOptions.independenceTurn, years, 468)
        ret = checkOp(GameOptions.ages, years) {
            let o = TextOption(id: GameOptions.ages, specification: self); o.setValue("1600,1700"); return o
        } || ret
        int(GameOptions.seasons, years, 2)
        bool(GameOptions.disembarkInColony, colony, false)
        bool(GameOptions.enhancedTradeRoutes, map, false)
        // @compat 0.11.6
        int(GameOptions.settlementNumberOfGoodsToSell, map, 3)
        pct(GameOptions.alarmBonusBuy, map, 20)
        pct(GameOptions.alarmBonusSell, map, 20)
        pct(GameOptions.alarmBonusGift, map, 40)
        bool(GameOptions.claimAllTiles, colony, false)
        // @compat 1.1.0
        bool(GameOptions.mapDefinedStartingPositions, map, true)
        return ret
    }

    /// Add a missing game option with a default (Java's checkOp).  The
    /// kind check uses the made option's class, as Java's does.
    private func checkOp(_ id: String, _ gr: String, make: () -> AbstractOption) -> Bool {
        let op = make()
        if let existing = allOptions[id], type(of: existing) == type(of: op) || existing.isKind(of: op) {
            return false
        }
        op.group = gr
        optionGroup(gr)?.add(op)
        addAbstractOption(op)
        return true
    }
}

extension AbstractOption {
    /// Whether this option is of another option's class or a subclass,
    /// like Java's Class.isAssignableFrom.
    func isKind(of other: AbstractOption) -> Bool {
        switch other {
        case is PercentageOption: self is PercentageOption
        case is RangeOption: self is RangeOption
        case is SelectOption: self is SelectOption
        case is IntegerOption: self is IntegerOption
        case is BooleanOption: self is BooleanOption
        case is TextOption: self is TextOption
        default: type(of: self) == type(of: other)
        }
    }
}

extension FoundingFather {
    /// Drop the events (for the Bolivar fix).
    func clearEvents() {
        setEvents([])
    }
}

extension Specification {
    /// The default nation colors (@compat 0.10.x/0.11.x), as ARGB.
    static let defaultColors: [String: Int32] = {
        let rgb: [String: UInt32] = [
            "model.nation.dutch": 0xff9d3c, "model.nation.french": 0x0000ff,
            "model.nation.english": 0xff0000, "model.nation.spanish": 0xffff00,
            "model.nation.inca": 0xf4f0c4, "model.nation.aztec": 0xc4a020,
            "model.nation.arawak": 0x6888c0, "model.nation.cherokee": 0x6c3c18,
            "model.nation.iroquois": 0x74a44c, "model.nation.sioux": 0xc0ac84,
            "model.nation.apache": 0x900000, "model.nation.tupi": 0x045c04,
            "model.nation.dutchREF": 0xcc5500, "model.nation.frenchREF": 0x6050dc,
            "model.nation.englishREF": 0xde3163, "model.nation.spanishREF": 0xffdf00,
            "model.nation.portuguese": 0x00ff00, "model.nation.swedish": 0x00bfff,
            "model.nation.danish": 0xff00bf, "model.nation.russian": 0xffffff,
            "model.nation.portugueseREF": 0xbfff00, "model.nation.swedishREF": 0x367588,
            "model.nation.danishREF": 0x91006d, "model.nation.russianREF": 0xbebebe,
        ]
        var result = rgb.mapValues { Nation.opaque | Int32(bitPattern: $0) }
        result[Nation.unknownNationId] = Nation.unknownNationRGB
        return result
    }()
}
