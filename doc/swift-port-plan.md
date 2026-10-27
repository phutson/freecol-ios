# FreeCol → Swift/SwiftUI: phased port plan

The approach: build a Swift engine with no UI first, and check it against
the Java game at every step. Only then put a UI on top. The Java code
serves as the reference for correct behavior throughout.

## Phase 0: Decisions and comparison tools (before any Swift)

### Decisions to make first

- **License:** FreeCol is GPL v2+, so a port must stay GPL. The App
  Store's terms have long been considered at odds with the GPL. Decide
  early whether this is a personal or sideloaded build, or something to
  publish.
- **Scope for version 1:** single-player only, the `classic` and `freecol`
  rulesets, iPad first (the map needs the screen space), iOS 17+, Swift 6.
- **Defer:** multiplayer, the metaserver, mods (other than how the rules
  files inherit from each other), the map editor, debug menus.

### Comparison tools, written in Java inside this repo

- **Spec dumper:** loads `data/rules/freecol/specification.xml` (which
  extends `classic`) and writes every resolved type, modifier, ability and
  option as sorted JSON.
- **Game-state dumper:** loads a save file and writes a canonical JSON
  snapshot (units, tiles, colonies, players, the market).
- **Turn recorder:** runs N turns with a fixed random seed and dumps the
  state after each turn.

These JSON files become the expected results for the Swift tests. The
Swift code is correct when its dumps match the Java ones exactly.

**Exit criteria:** the dump tools run under `ant`, and a set of reference
files is committed (spec dumps plus about 10 save games of different eras
and sizes).

### Status: dump tools implemented

The tools are in `src/net/sf/freecol/tools/dump/`. Every dump is
canonical JSON (sorted keys, fixed indentation, shortest float form), so
the Java and Swift outputs can be compared with a plain `diff`. Each dump
has two parts:

- `xml`: FreeCol's own XML serialization as a tree (`tag`, `attrs`,
  `children`, `text`). This checks loading and save compatibility.
- `derived`: values the rules engine computes, such as resolved abilities
  and modifiers, combat strength, potential production, colony net
  production, market prices and path costs. This checks the logic.

| Tool | ant target | Output |
|---|---|---|
| `SpecDump` | `ant dump-spec [-Drules="classic freecol"]` | `build/dumps/spec/spec-<rules>.json` |
| `GameDump` | `ant dump-game -Dsavegame="a.fsg b.fsg" [-Drules=freecol]` | `build/dumps/games/<name>.json` |
| `TurnRecorder` | `ant record-turns [-Dseed=1 -Dturns=20 -Dsave.every=10]` | `build/dumps/turns-<rules>-seed<n>/turn-NNN.json` and `.fsg` |

Notes:

- `.fsm` map files have no rules of their own, so `GameDump` needs
  `--rules` (or `-Drules`) for them.
- The game UUID is masked in dumps, because Java generates it with
  `UUID.randomUUID()` rather than the game's random number generator.
  With that masked, two recordings with the same seed are byte-identical.
- `TurnRecorder` runs the server's own turn processing (`csNextTurn` and
  `csNewTurn`), but players don't move: the AI runs through connections
  and threads and isn't reproducible yet. So recorded games have no
  colonies. Colony and pathfinding values need real saves from played
  games, dumped with `GameDump`.
- Each turn's JSON is about 2.5 MB for the default 40×100 map, so commit
  a selection rather than every turn.
- **Java bug found by these tools (fixed):** each save/load cycle added
  another copy of `model.ability.dressMissionary` to every `Europe`.
  `Europe.getAbilities()` adds that ability on the fly, `writeChildren`
  saved it, and `readChild` then stored it as a real ability. Now
  `writeChildren` writes only the stored abilities, and `readChild` drops
  stored copies of that ability (marked `@compat 1.1.0`), which cleans up
  older saves. A save now reloads to an identical snapshot. The Swift
  port should match the fixed behavior: never save or store that ability.

## Phase 1: The `common/model` foundation (~67k lines of Java, 124 files)

### 1a. Remove UI dependencies on the Java side first

Twelve model files import Swing, AWT or client classes: `Area`,
`BuildableType`, `BuildingType`, `Europe`, `ModelMessage`, `Map`,
`Nation`, `Player`, `Settlement`, `Specification`, `TradeLocation`,
`UnitType`. Most of it is `java.awt.Color`, `JList`/`ListModel`,
`ImageLibrary` and `panel.Utility`. Moving those uses out first makes the
layer being ported purely about game logic, and it's a worthwhile cleanup
for the Java codebase anyway.

#### Status: done

`common/model` no longer imports anything from `java.awt`, `javax.swing` or
`net.sf.freecol.client`.

| Was in the model | Now |
|---|---|
| `java.awt.Color` in `Nation`, `Player`, `Area`, `Specification` | ARGB `Integer`s in the `Color.getRGB()` form: `Nation.getRGB()/setRGB()`, `Player.getNationRGB()`, `Area.getRGB()`, `Nation.UNKNOWN_NATION_RGB`. The client converts with `ImageLibrary.toColor()` and `getNationColor(Player/Nation)`. |
| `JList`/`ListModel` parameters of `getMinimumIndex`/`getMaximumIndex` in `BuildableType`, `BuildingType`, `UnitType` | Take a `List<BuildableType>`. The rules stay in the model, and `BuildQueuePanel` passes its list contents. |
| `getLocationImageKey()` in `Location`, `Europe`, `Settlement`, `Map` | `ImageLibrary.getLocationKey(Location)` |
| `getNameAsJlabel()` in `TradeLocation`, `Europe` | Built in `TradeRouteInputPanel` |
| `ModelMessage.splitLinks()` (makes Swing buttons) | Private method in `ReportTurnPanel` |

Checks: the full `AllTests` suite passes (430 tests). The Phase 0 dumps
before and after are identical: both specs, 6 recorded turns, and a map,
including nation colors in the saved XML.

Not checked: the Swing client wasn't started, so the changed drawing code
(nation colors on the map, minimap, chat and players table) hasn't been
looked at on screen. Those changes are mechanical conversions.

**UI dependencies outside `common/model`** are still there. They're mostly
for later phases:
- `common/networking`: 50 message classes import client controllers for
  their client-side handlers. Phase 3 replaces this layer.
- `common/resources`, `common/io/sza`, `common/util/ImageUtils`: image,
  font and color loading. Phase 2.
- Small ones that block porting `common/*` in Phase 1:
  `FreeColSavegameFile` (`MapGeneratorOptionsDialog`), `OptionGroup` and
  `ServerPlayer` (`ClientOptions`), `Messages` (`UIManager`),
  `StringUtils` (`FontMetrics`), `Utils` (screen helpers), `FreeColDirectories`
  and `FreeColDataFile` (Swing file chooser classes), `common/debug`.
- In the server: `java.awt.Rectangle` in `SimpleMapGenerator` and
  `ServerRegion`, `BufferedImage` in `FreeColServer`, `Color` in
  `PreGameController`.

**Order-dependence found while checking:** `Modifier.hashCode()` includes
`ModifierType`'s enum hash, which is based on object identity. So the
order of modifiers in the hash sets changes with unrelated code changes
and JVM versions. The dump tools now sort sibling `ability`/`modifier`
elements to make the order reproducible.

**Modifier application order (checked and fixed):**
`FeatureContainer.applyModifiers` sorts with
`Modifier.ascendingModifierIndexComparator`. That already ordered mixed
types at the same index (additive, then multiplicative, then percentage),
then by id and source. But it wasn't a total order. Two modifiers with
the same index, type, id and source but different values were applied in
hash-set order, and float rounding makes that matter: 2 with −60% then
+25% is 0.99999994 (truncates to 0), but in the other order it's 1.0
(truncates to 1). The shipped rules have no such ties (every tie is the
same operation, differing only in scope or duration), so results don't
change. But mods could create them.

The comparator now also orders by value, increment type, increment,
first turn and last turn. Anything still tied applies exactly the same
operation. `ModifierTest.testTiedModifierOrder` covers this. **The Swift
port must use this same order**: index → type (additive, multiplicative,
percentage) → id → source id → value → increment type (none first) →
increment → first turn → last turn (none first), using `Float`
arithmetic.

### 1b. Swift package layout

```
FreeColKit/                 (Swift Package, no UIKit/SwiftUI imports)
  FreeColCore/              model types, Game, Map, Specification
  FreeColIO/                XML reading/writing, .fsg save files
  FreeColI18n/              .properties loader, StringTemplate
  FreeColServer/            (Phase 3)
  FreeColEngine/            (Phase 3) the actor the UI talks to, and snapshots
  FreeColAI/                (Phase 4)
FreeColApp/                 (Phase 5) SwiftUI (map in Canvas; SpriteKit if needed)
```

Keeping the engine in a package lets it build and test on macOS with
`swift test`, with no simulator needed.

#### Status: done

The package is at `swift/FreeColKit/` (Swift 6 language mode, iOS 17+,
macOS 14+). It builds with `swift build` and for the iOS Simulator with
`xcodebuild`. Compared with the layout above:

- **Two extra low-level modules.** In Java, model classes read and write
  their own XML, so the XML layer has to sit *below* the model, not
  beside it:

  ```
  FreeColIO, FreeColI18n      saved games, rules files / translated strings
          \      /
        FreeColCore           model and rules (common/model, common/option)
          /      |
  FreeColXML     |            FreeColXMLReader/Writer equivalents
          \      |
        FreeColUtil           java.util.Random port, Java rounding, helpers
  ```
- `FreeColServer` and `FreeColAI` are added in Phases 3 and 4, not as
  empty targets now.
- Each module has only a placeholder naming its Java source packages
  until its port step.
- No third-party packages. Saved games are zip archives; step 5 added a
  small zip reader (`FreeColIO/ZipArchive`) instead of ZIPFoundation, so
  the package still needs no network fetch.

**Comparison tooling on the Swift side** (`Tests/FreeColTestSupport`):

- `JSONValue`: a JSON parser that keeps `2` and `2.0` apart, which
  Foundation's `JSONSerialization` doesn't.
- `CanonicalJSON` and `JavaNumberFormat`: write the exact format of the
  Java dump tools, including Java's `Double.toString`/`Float.toString`
  layout (`1.0E7`, `9.9E-4`). Checked against values printed by JDK 18.
  Java always prints two significant digits, picking the closest
  two-digit decimal when the shortest form has one. That only matters
  for the smallest subnormals (`4.9E-324`, and `1.4E-45` for
  `Float.MIN_VALUE`, the "unknown" modifier value). Handled since step 2,
  and the code now lives in `FreeColUtil`.
- `ReferenceDumps`: finds the dumps in `$FREECOL_REFERENCE_DIR` or
  `build/dumps`. Tests that need dumps are skipped when there are none.
- `ReferenceDumpRoundTripTests`: every Java dump (2 specs, 11 turns, a
  map, the manifest) comes out **byte-identical** after a Swift parse and
  rewrite. So once the Swift engine produces the same values, a plain
  file comparison is enough to check it.

**Making the dumps:** `swift/scripts/make-reference-dumps.sh` compiles
the Java game with `javac` (no `ant` needed) into `build/dump-classes`
and writes `build/dumps` in about 20 seconds. `SEED`, `TURNS` and `MAPS`
override the defaults.

Also fixed in the dump tools: saving a game made FreeCol create an empty
`freecol/` directory in the current directory, because the user
directories were never set up. The tools now point them at a temporary
directory.

**Running the tests:**

```
sh swift/scripts/make-reference-dumps.sh
cd swift/FreeColKit && swift test
```

To check every bundled map against Java (step 5), not just four:

```
cd swift/FreeColKit && FREECOL_ALL_MAPS=1 swift test -c release
```

### 1c. Key design choices

- **Classes, not structs, for game objects.** The model is a graph full of
  back-pointers (a unit points to its tile, the tile to its colony, the
  colony to its owner). Rule types (`UnitType`, `GoodsType`, …) are
  read-only after loading and can be shared freely.
- **Ownership (decided in step 1):** the same as Java's.
  - The game's registry holds objects **weakly**, as Java's
    `WeakReference` map does.
  - Containment holds them **strongly**: the game owns players and the
    map, a player owns its units and colonies, and so on.
  - Back-references (an object's `game`, and later a unit's owner or
    location) are **weak**, so ARC sees no cycles.
  - An object that nothing contains disappears from the registry right
    away. Java keeps it findable until the garbage collector runs, so game
    logic must never depend on that delay.
  - Rule objects hold their `Specification` strongly, since the
    specification doesn't point back at them through that property.
- **Reproduce Java's numbers exactly**, or the comparison tests will fail
  on tiny differences:
  - Port `java.util.Random` exactly (it's a short, well-documented
    algorithm). Swift's built-in random generators produce different
    sequences.
  - `Math.round` rounds halves upward (−2.5 → −2), while Swift's
    `.rounded()` rounds them away from zero (−2.5 → −3). Write a
    `javaRound()` helper.
  - Keep `float` as `Float`, not `Double`, wherever the modifiers and
    production calculations use it.
  - Integer division, `%` and `Math.floor` behave the same in both
    languages. **`(int)` casts don't:** Java saturates at the type's
    limits and turns NaN into 0, while Swift's `Int32(x)` crashes. Use
    `JavaMath.toInt`/`toLong`.
  - Java's int arithmetic wraps on overflow and Swift's traps. Use
    `&+`, `&-` and `&*` wherever Java code can overflow (hash
    calculations, random number code).
  - Java strings compare, hash and index by UTF-16 code units, and Swift
    by Unicode characters. Use `JavaString` where order or offsets matter.
- **XML parsing:** Foundation's `XMLParser` is a streaming parser like the
  StAX one FreeCol uses now (`FreeColXMLReader`), so the existing
  `readAttributes` / `readChildren` structure translates almost one to one.
  A protocol replaces the inherited `readFromXML` / `toXML` methods.
- **Save files:** `.fsg` files are zip archives containing `savegame.xml`.
  iOS has no zip file API, but Apple's Compression framework does raw
  deflate, so reading needs only a small reader for the zip structure
  (done in step 5). Writing will need a matching writer in step 10.
- **Java streams** (`java.util.stream` and `java.util.function`, used in
  about 80 imports) map well onto Swift's `map`/`filter`/`reduce`. Port
  `common/util/CollectionUtils` as Swift extensions first, because it's
  used everywhere.

### 1d. Port order (each step builds on the ones before it)

1. **Base objects:** `FreeColObject`, `FreeColGameObject`,
   `FreeColSpecObject`, `ObjectWithId`, `Named`, and `common/util` helpers.

   **Status: done.**

   - **`FreeColUtil`:**
     - `JavaRandom`: an exact port of `java.util.Random`, covering the
       methods FreeCol uses (`nextInt`, `nextInt(bound)`, `nextFloat`,
       `nextDouble`, `ints(n, origin, bound)`, `shuffle`). It also reads
       and writes the saved-game random state, which is Java's object
       serialization of the `Random` in hex, so a Swift game can
       continue a Java game's random sequence.
     - `RandomUtils`, with an optional per-generator `trace` that
       produces the same text as Java's FINEST logging, for finding where
       random sequences start to differ.
     - `JavaMath` (`Math.round`, saturating casts) and `JavaString`
       (`hashCode`, `compareTo`, `parseInt` with Unicode digits,
       `startsWith`, `lastPart`, UTF-16 offsets).
     - `JavaNumberFormat`, moved here from the test support.
   - **`FreeColCore`:**
     - `FreeColObject`: identifiers, `compareIds`, class index,
       equality and hashing as in Java, and the specification/game hooks.
     - `FreeColSpecObject`, `FreeColGameObject` (registration, `internId`,
       disposal), and `ObjectWithId`/`Named` as protocols.
     - The registry part of `Game`, and an identity-only `Specification`.
   - **Deferred to the steps that need them:** abilities and modifiers
     (step 2), XML reading and writing, `copyIn`, `getLinkTarget`,
     `checkIntegrity`. Java's `PropertyChangeSupport` is only used by the
     Swing client, so it isn't ported.
   - **Tests check against Java itself.** `tools/dump/JavaCompatOracle`
     writes what the JDK computes into
     `swift/FreeColKit/Tests/JavaOracle/java-compat.json` (about 200 KB,
     kept with the tests so they always run). It covers:
     - `Random` for 7 seeds: every method, 13 bounds, shuffles, a mix of
       calls, and saved state before and after restoring;
     - `Math.round` and casts for over 200 floats and doubles;
     - string hashing, ordering and parsing;
     - the identifier rules and `compareIds` for 18 ids.

     47 Swift tests pass. A deliberately broken version of the `ints`
     algorithm fails them, so they do catch mistakes.

   Found while porting:
   - **`Random.ints()` depends on the JDK version.** JDK 17+ uses a
     different bounded algorithm from JDK 11, and it gives different
     numbers in 21 of the 91 cases tested. The port follows JDK 17+ (the
     oracle came from JDK 18.0.1.1). A Java game run on JDK 11 makes
     different random decisions wherever `RandomUtils.randomInts` is used.
   - **Some shuffles never use the game's random number generator:**
     `EuropeanAIPlayer` (line 2493) and `NameCache` (line 223) call
     `Collections.shuffle(list)` with Java's global generator, so those
     results aren't reproducible in Java either. Fix these in Java before
     comparing AI turns (Phase 4).
   - **Java `HashMap`/`HashSet` iteration order.** Swift's hashing is
     seeded randomly per process, so any ported loop over a hash container
     that consumes random numbers or produces ordered output must get an
     explicit order. `Game.freeColGameObjects` returns identifier order;
     Java's is `HashMap` order.
2. **The modifier system:** `Feature`, `Modifier` (additive,
   multiplicative and percentage, applied in index order), `Ability`,
   `Scope`, `FeatureContainer`. This is small but every production and
   combat calculation depends on it, so test it heavily.

   **Status: done.**

   - **Ported:** `Feature`, `Modifier` (with Java's `toString`, timed
     modifiers and the total application order), `Ability`, `Scope`,
     `FeatureContainer`, and the feature methods on `FreeColObject`. Also:
     - `Turn`, as a value type with an explicit `TurnCalendar` instead of
       Java's static fields;
     - a minimal `FreeColSpecObjectType` holding a feature container;
     - all 80 ability and 41 modifier id constants, generated from the
       Java source (`ADD_TAX_TO_BELLS` becomes `Ability.addTaxToBells`).
   - **Replacing Java reflection:** scopes call methods by name in Java.
     Here an object answers through `scopeType` (Java's `getType()`) and
     `scopeMethodValue(_:)`. Anything not answered behaves as Java does
     when the method is missing: it compares as `"null"`. The modifiers
     in the rules only use `isIndian`, `isWater` and `isForested`, which
     each class answers when it's ported.
   - **Ownership:** a feature holds its `source` weakly, because a
     colony's features often name the colony as their source.
   - **Lookups return a fixed order** (modifiers in application order,
     abilities by id, source and value) rather than Swift's per-run set
     order.
   - **Deferred:** `Feature.isIndependent`, which needs the rule types
     from step 3; XML reading and writing; `copyIn`.
   - **Tests check against Java.** `FeatureOracle` (part of
     `JavaCompatOracle`) records:
     - 400 randomized modifier sets with deliberate ties: result,
       per-turn values, Java's sorted order and `toString`;
     - 150 scopes against 5 targets;
     - 50 feature containers with 80 lookups each (`hasAbility`, counts,
       `apply`);
     - 151 equality pairs, timed modifiers, and three turn calendars.

     The Swift tests also apply each modifier set in shuffled orders.
     64 tests pass, and three deliberately introduced bugs each fail
     hundreds of checks.

   Found while porting:
   - **Equivalent formulas aren't interchangeable.** Writing the
     percentage step as `base * (1 + v/100)` instead of Java's
     `base + base*v/100` is mathematically the same, but its float
     results differ in 347 of the checks. Port arithmetic exactly as
     written.
   - **Two "get all" methods filter differently.** Java's no-argument
     `getModifiers()` returns every modifier unfiltered (`allModifiers`
     here), while `getAbilities()` and `getModifiers(null, …)` filter
     with a null target. So modifiers whose scopes don't match null are
     left out of the latter. Both behaviors are kept.
   - **An empty scope container isn't the same as none.** Java's
     `ScopeContainer.equalScopes` treats a cleared container as different
     from a missing one, which changes feature equality. This is kept.
   - **A commented-out example in the rules uses a method that doesn't
     exist.** The founding-father scope example in `specification.xml`
     uses `getNationID`, but `Player` has `getNationId`. It's only a
     comment now, but copying it would match nothing.
3. **Rule types:** `FreeColSpecObjectType` and its subclasses `GoodsType`,
   `TileType`, `ResourceType`, `TileImprovementType`, `UnitType`,
   `BuildingType`, `Role`, `NationType`, `Nation`, `FoundingFather`,
   `ProductionType`, `UnitChangeType`, `Disaster`, and so on.

   **Status: done**, with a shifted boundary. Rule types only exist by
   being read from the rules XML, so testing them against Java needed
   XML reading and part of `Specification` now:

   - **Ported:**
     - `FreeColSpecObjectType` in full;
     - `BuildableType`, `GoodsType`, `ResourceType`, `ProductionType`,
       `AbstractGoods`;
     - `TileType`, `TileTypeChange`, `TileImprovementType`;
     - `BuildingType`, `Role`, `UnitType`, `UnitTypeChange`,
       `UnitChangeType`;
     - `NationType`, `EuropeanNationType`, `IndianNationType`,
       `SettlementType`, `PlunderType`, `RandomRange`, `Nation`,
       `FoundingFather`;
     - `Event`, `Limit`, `Operand`, `Disaster`, `Effect`, `AbstractUnit`,
       `TypeCountMap`, `RandomChoice`;
     - every class's XML reading, including the 0.10/0.11 compatibility
       attribute names.
   - **`FreeColXML`:** `FreeColXMLReader`, a pull reader with Java's
     cursor API (`nextTag`, `moreTags`, `closeTag`, typed attributes) over
     a document parsed by `XMLParser`. Attributes follow Java's parsing:
     `Integer.decode` reads `"010"` as 8, and `Float.parseFloat` accepts
     `"1.5f"` and hex floats.
   - **`Specification`:** the type registry with forward declarations,
     the section readers (`TypeReader`), and the ability and modifier
     registries. Also the option-independent part of `clean()` (derived
     lists, experts, nations), and the lookups.
   - **Reading resolved specs:** Swift reads the *resolved*
     specification, the XML Java sends to clients and writes into saved
     games. Option *values* are read for the specification's own
     difficulty level, so `getString`/`getInteger`/`getBoolean` work.
   - **Deferred to the steps with game objects:** methods that need
     `Colony`, `Unit`, `Player`, `Tile`, `Settlement` or `Market`, such as
     `canBeBuiltInColony`, building potential production, limit
     evaluation, plunder and labels.
   - **Tests:** `SpecDump` now also writes the resolved XML. Swift reads
     `classic`, `freecol` and `freecol` at veryHard difficulty, then
     compares every derived value of every type (features, combat
     values, production, upgrades, consumption and more) with Java's.
     They all match, apart from one documented `applyFixes` difference.
     79 tests pass in total.

   Found while porting:
   - **Java `HashMap` order shows up in results**, so `FreeColUtil` now
     has `JavaHashMap`, which reproduces `java.util.HashMap` iteration
     (buckets, resizing, JDK 18 presizing for copies and `putAll`).
     It's checked against Java on 60 maps, where a copy iterates
     differently from its original in 13. Without the hash spreading,
     30 values per spec differ (for example the order of a brave's
     consumed goods). `TypeCountMap`, event limits, starting units, unit
     changes and the type registry all use it.
   - **A Java compatibility fix runs again on every load.**
     `applyFixes` adds a source-less `coastalOnly=false` ability to the
     custom house whenever `hasAbility(coastalOnly)` is false, which is
     always the case when its value is false. A Java client reading the
     resolved XML has the extra ability too (checked), so Swift will
     match once `applyFixes` is ported in step 4. This is recorded as a
     known issue in the test.
   - **Inheritance isn't exercised yet.** The resolved XML has no
     `extends` attributes (Java has already flattened them), so the
     ported inheritance code is first tested in step 4 against the raw
     rules. A deliberately broken inheritance went unnoticed here.
   - **The resolved spec contains every difficulty level's options.**
     Taking the last value found gave the wrong (veryHard) values; now
     only the chosen level counts.
   - **Two Java behaviors that look like bugs, kept as they are:**
     - `Specification.clean()` never clears `buildableUnitTypes`, so
       cleaning twice duplicates the list.
     - `TileTypeChange` reads no id and compares by id, so all changes
       compare equal.
   - **`UnitTypeChange` numbering differs.** Java numbers unnamed
     changes with a process-wide counter; Swift counts per
     specification, so the generated ids can differ when several
     specifications are loaded.
   - **Java's static `Source` objects** are per-specification in Swift,
     since Swift 6 doesn't allow mutable shared statics. Lookups by id
     behave the same.
4. **`Specification` (3.3k lines) and the options in `common/option`:**
   this includes `extends=` inheritance, abstract types and `extends`
   inside type definitions.
   - **Already done in step 3:** the type registry, the section readers,
     and reading resolved specs with option values.
   - **Left for this step:**
     - reading the raw rule set files, with `extends` between rule sets
       (`freecol` extends `classic`) and within types, abstract types,
       `delete` and `preserve`;
     - mods;
     - the option classes;
     - difficulty levels (`prepare`);
     - the compatibility fixes (`applyFixes`);
     - the option-dependent part of `clean()` (turn calendar, ages,
       customs on coast).
   - ✅ **Milestone:** the Swift spec dump matches the Java dump for both
     `classic` and `freecol`, read from the raw rules files.

   **Status: done. Milestone reached**, and extended to a second
   difficulty level and all 15 mods that change the rules.

   - **Options (`FreeColCore/Options.swift`):** `AbstractOption`,
     `OptionGroup`, and the integer, percentage, select, range, boolean,
     string, text, file, unit type, unit and unit list options. Each
     reads its XML and has Java's `toString`.
     - The 21 Java classes become one non-generic hierarchy, since
       Java's `Option<T>` doesn't map onto Swift subclassing.
     - Not ported: the client-only options (audio mixer, language, mod
       list), and merging option groups, which comes with game setup.
     - `GameOptions` and `MapGeneratorOptions` ids (143) are generated
       from the Java source.
   - **`Specification` (`Specification+Fixes.swift`):**
     - the option registries and the option reader;
     - `extends` between rule sets, through a `RulesSource`;
     - deleting types, and partial reads (mods use `partial="true"` to
       change single attributes; Java does it by reflection, here each
       class lists the setters Java has);
     - mods (`loadMods`);
     - `prepare` (fixes, advantages, difficulty level);
     - `applyFixes` with all seven fix functions;
     - the rest of `clean()`: option choices, the turn calendar (now held
       per specification instead of in Java's static `Turn` fields), the
       ages and the customs-on-coast rule.
     - `Specification.loadRules` follows `FreeCol.loadSpecification`
       exactly: read, prepare with the file's own difficulty, clean, then
       prepare again with the chosen difficulty (without cleaning again).
   - **`FreeColIO`:** `FreeColDataDirectory` finds rule sets and mods by
     their `mod.xml` ids, and finds compatibility files in `data/base`.
   - **Tests:**
     - The Java dump now includes every option (class plus `toString`),
       every option group (members and flags), the ages, the turn
       calendar and the difficulty level. `SpecDump` takes `--mods`.
     - Swift loads `classic`, `freecol` (medium and veryHard) and
       `freecol` with each of the 15 mods straight from `data/`, and every
       value matches Java.
     - Reading the resolved XML now matches too. The custom house
       difference from step 3 is gone now that the fixes run.
     - 82 tests pass, with no known issues.
     - Deliberately broken unit type inheritance, rule set `extends` and
       difficulty application each fail 17–18 checks.

   Found while porting:
   - **Most compatibility fixes are no-ops on the current rules.** For
     example, the rules already contain the cargo penalty modifier, so
     removing that fix changes nothing. The fixes get real coverage when
     saved games from old versions are ported (step 10).
   - **Every difficulty level registers the same option ids.** Until
     `prepare` applies the chosen level, the last level read wins. So
     `clean()` (run before the second `prepare`) sees those values; it
     only reads game options, so this doesn't matter today.
   - **The `testing` rule set has no `mod.xml`,** so Java's rules loader
     ignores it; only Java's unit tests use it, by path. It also isn't
     loadable here.
   - **A Java quirk mirrored as-is:** `customsOnCoast` changes an
     ability's value while it sits in a hash set whose hash includes the
     value, so lookups of that ability can miss afterwards. Iteration
     still works.
   - **The oracle files kept with the tests are now 8.2 MB:** the library
     oracle, three resolved specs and 15 mod dumps.
5. **Map and game structure:** `Game`, `Map` (2.9k lines), `Tile`,
   `Region`, `TileImprovement`, `TileItemContainer`, `LostCityRumour`.

   **Status: done.** The bundled maps and a recorded game load in Swift,
   and every map, tile and region value Java computes from them matches.

   - **Ported (`FreeColCore`):**
     - `Map` with `Position`, `Layer` and the spiral `CircleIterator`;
       geometry (distance, direction, rough direction, neighbours, sub
       maps, closest and random land tiles, shuffles); regions;
       latitudes; `resetContiguity`, `resetHighSeasCount`,
       `resetHighSeas`, `resetLayers`, `fixupRegions`,
       `collectStartingTiles`, `importTile`.
     - `Tile`: items, rivers and roads, geography (shore, landlocked,
       polar, river corners, good hill, mountain and river tiles),
       defence, work amounts and allowed improvements, disasters, and
       production: `potentialProduction`, `maximumPotential`, the
       sorted potentials and the best food.
     - `TileItem`, `TileItemContainer`, `TileImprovement` (with
       `TileImprovementStyle` as a value type, and the river and road
       connection updates), `Resource`, `LostCityRumour`, `Region`,
       `Direction`.
     - `TileProductionCalculator`, `WorkerAssignment`, `ProductionInfo`
       and the tile part of `ProductionUtils`.
     - `Game`: players, the map, turn, Spanish succession, UUID, the
       cities of Cibola, and the specification saved in a game.
     - Reading references the way Java's reader does
       (`GameObjectReading.swift`): `lookup`, `findFreeColGameObject`,
       `makeFreeColObject`, `readFreeColObject` and
       `getLocationAttribute`, with a `GameObjectReadable` protocol in
       place of Java's reflective `newInstance`.
     - `Player`, `Settlement`, `Colony` and `IndianSettlement` are stubs
       holding only what tiles refer to (identity, name, owner, tile).
       Their contents are skipped when reading, until steps 7 and 8.
   - **Ported (`FreeColIO`):** `ZipArchive` (stored and deflated entries,
     CRC checked) and `FreeColSavegameFile`, with `readGame` following
     `FreeColServer.readGame`: version check, the server random state,
     the game, and skipping the AI.
   - **Not yet ported**, listed in each class's header comment: units on
     tiles and everything that needs them; players' cached tiles (skipped
     when reading); path finding (step 9); the `Location` interface (step
     6); writing XML; `copyIn` and `checkIntegrity`; labels.
   - **Ownership:** the game holds its players and map, the map its tiles
     and regions, a tile its item container and settlement, a region its
     children. Owners, owning settlements, regions on tiles, parent
     regions and items' tiles are weak. Objects created because something
     referred to them before they were read (a tile naming a settlement
     defined later) are kept alive by the reader until reading ends, as
     Java's references keep them. A test checks that dropping the game
     frees everything.
   - **Tests:**
     - New Java tool `MapOracle` records, for each game: the players, the
       map and its regions, about 40 values for every tile, geometry
       queries around 17 sample tiles, seeded random queries, and the
       results of recomputing contiguity, high seas counts, layers and
       high seas placement. The high seas are then placed a second time,
       far from land, so the code marking edge ocean as leading to Europe
       runs, and each limited resource's bonus is also recorded with one
       unit left, so its quantity limit applies.
     - Inputs: the 23 maps in `data/maps` (read from there) and a game
       recorded by `TurnRecorder` (`Tests/JavaOracle/games`, 75 KB,
       written only if missing so it never changes).
     - Full dumps for a small map and the recorded game are zipped in
       `Tests/JavaOracle/maps/full.zip` (287 KB) and compared value by
       value. Every map has a SHA-256 of its dump in `maps/digests.json`,
       and Swift computes the same document and hash.
     - A debug build takes 10–15 seconds per map, so `swift test` checks
       the two full dumps and two more maps by digest. All 24 inputs are
       checked with `FREECOL_ALL_MAPS=1 swift test -c release`, in under
       2 minutes (Java's `MapOracle` takes 1).
     - All values match Java for all 24 inputs. The map oracle
       regenerates byte for byte.
     - 92 tests passed (36 seconds) at the end of step 5, and the
       package built for the iOS Simulator.
     - Deliberate bugs: ignoring an improvement's magnitude fails 431
       checks per input, not marking edge ocean for Europe 1,673 and
       2,234, and ignoring a resource's quantity limit 8 and 17. The last
       two went unnoticed until the oracle gained the extra checks above.
       Swapping two steps of the spiral iterator makes it never end, so
       the tests hang instead of failing.

   Found while porting:
   - **A bug from step 3:** `TileType` didn't answer the `isWater` and
     `isForested` methods that scopes name, so no improvement was
     allowed on any tile type. The spec tests didn't use those scopes.
     The map tests found it at once: Swift allowed no roads, plowing or
     rivers anywhere.
   - **Ties in sorted potential** are broken by goods type order, through
     Java's `descendingAmountComparator`.
   - **Java reads saved games as server classes.** `ServerRegion` prints
     its size and bounds in `toString`, and class names gain "Server", so
     the oracle avoids both.
   - **`JavaHashMap` lookups were slow:** each one computed Java's string
     hash by walking UTF-16. It now keeps a native dictionary for lookups
     and Java's table only for iteration order; the map tests got 40%
     faster.
   - **A Java quirk mirrored as-is:** `resetContiguity` numbers the land
     masses from 0 again after the water masses, because Java passes the
     counter by value. So the first land mass and the first ocean share
     number 0, and `isConnectedTo` says a land tile and a water tile are
     connected when their numbers match. Path finding uses contiguity to
     decide whether a path can avoid a carrier, so this may matter in
     step 9.
6. **Locations and containers:** `Location`, `UnitLocation`,
   `GoodsContainer`, `Goods`, `AbstractGoods`.

   **Status: done.** The units in the bundled maps and the recorded game
   are read where Java reads them (tiles, carriers, native settlements,
   Europe, the high seas), and everything Java computes about them,
   their locations and their goods matches.

   - **Ported (`FreeColCore`):**
     - The `Location`, `Locatable` and `Ownable` protocols, and
       `NoAddReason`.
     - `UnitLocation` and `GoodsLocation`. `Tile` is now a
       `UnitLocation`; `Settlement` and `Unit` are `GoodsLocation`s.
       `Map` is a `Location`, and tile items are `Locatable`.
     - `GoodsContainer` (in Java's `HashMap` order, with save, restore,
       remove above, moving goods) and `Goods`. `AbstractGoods` was
       already done apart from labels and `evaluateFor`, which need
       i18n and markets.
     - `HighSeas` in full.
     - **The first part of `Unit`:** everything it reads from a save,
       its abilities and modifiers (type, role, owner, location), and what
       it does as a location and as cargo: space, holds, what it can
       carry or be added to, where it is (`up`, rank, carrier, Europe).
       The rest of `Unit` is step 7.
     - **Stand-ins that grew:** `Player` now reads its nation type,
       founding fathers, own abilities and modifiers, Europe and high
       seas. `Europe` reads its units and features (including the
       dress-missionary ability Java always adds). `Settlement` reads its
       units and goods, and has Java's rank, `up` and add rules.
   - **Simplified until step 7:** Java's `setState` and `setLocation`
     have side effects (moves, work, colony updates). For now, adding a
     unit to a ship or a tile sets its state directly, and `setLocation`
     only moves the unit between locations. Both are marked in the code.
   - **Ownership:** a location holds its units, a goods location its
     container, a player its Europe and high seas. A unit's location,
     owner, destination, entry location, teacher, student and home
     settlement are weak, as are a container's parent, goods' location
     and the high seas' destinations. A test checks that dropping the
     game frees units, containers, Europe and the high seas.
   - **Tests:**
     - `MapOracle` gained three sections: every unit (about 40 values
       each), every unit location (contents, capacity, what can be added:
       the units nearby, a unit of another player, goods of each type in
       four amounts), and every goods container, including a fixed
       sequence of changes to each. Players now include their features.
       To reach code the data doesn't, each ship also records its loads
       with a part-filled hold.
     - All values match Java for all 24 inputs. The full dumps are now
       340 KB zipped.
     - New `LocationTests` check that units are where they say, goods
       know their locations, goods move between holds, cargo space adds
       up, and the game owns everything.
     - 97 tests pass in 49 seconds; all 24 maps take 3 minutes in a
       release build; the package builds for the iOS Simulator.
     - Deliberate bugs: not counting part-filled holds fails 322 and 224
       checks, a wrong goods hash order 1,123 and 741, ignoring
       part-filled holds when loading 242 and 178, dropping the enemy
       occupation test 40 and 5, ignoring the owner's abilities 242 and
       187. The last three went unnoticed until the oracle gained the
       extra checks above.

   Found while porting:
   - **Java's `GoodsContainer.toString` cuts two characters when there are
     no goods**, so an empty container prints as `[goodsContainer:5371]]`.
     Mirrored, as the oracle records it.
   - **Sorting the game's object registry was slow**, as each comparison
     split both identifiers again. Working out the parts once per object
     halved the time of the detailed map tests.
   - **Java's `readList` returns without closing the element when the
     length attribute is missing**, which would confuse the rest of the
     read. FreeCol always writes the length, so the Swift version simply
     closes the element.
7. **Units and settlements:** `Unit` (5k lines), `Settlement`, `Colony`
   (3.3k), `Building`, `ColonyTile`, `WorkLocation`, `IndianSettlement`.

   **Status: done.** Colonies and native settlements are read in full,
   and what Java computes about them (production, consumption, build
   queues, education, export data, native prices and wanted goods) and
   about every unit's rules and moves matches.

   - **Ported (`FreeColCore`):**
     - `Settlement` in full: type, owned tiles, features, radius and
       line of sight, port connections, consumption, what it can
       provide.
     - `WorkLocation`, `Building` and `ColonyTile`, with occupations,
       suggestions and production. `BuildingProductionCalculator`,
       `ProductionMap`, `ProductionCache`, `BuildQueue`, `ExportData` and
       the `Consumer` protocol (`ColonyProduction.swift`).
     - `Colony` in full apart from what needs the server or messages:
       production and its cache, net production, sons of liberty and
       Tories, build queues and what can be built (with `Limit`
       evaluation), education, warehouses, food and horses, unit
       joining and leaving, the rules for claiming and abandoning.
     - `IndianSettlement` in full: contact levels, alarm and `Tension`,
       missionaries, owned units, prices, wanted goods, gifts, trade
       amounts.
     - **The rest of `Unit` (`UnitRules.swift`):** `setState` and
       `setLocation` with Java's side effects, work types and
       production, type and owner changes, roles (military, automatic,
       captured equipment), experience and teaching, unit changes,
       moves left, and `MoveType` with every naval, land, trade,
       learning and missionary rule and the move cost. Also line of
       sight, attack and ambush tests, treasure, and the AI's pioneer and
       scout scores.
     - **`Player` grew** gold, liberty and immigration, units and
       settlements, stances and tensions, land prices and claim rules,
       mission bans, the entry tile, and the scope methods rules ask
       about.
   - **Simplified until later steps:** trade routes (step 8), so
     `couldMove` never sees one; anything that sends messages or needs
     the server (Phase 3); telling the AI about an owner change (Phase
     4).
   - **Java recomputes production types when reading**, through
     `Unit.readAttributes` and `Game.readChildren`. Swift does the same,
     or work locations would show different production.
   - **Tests:**
     - None of the earlier inputs had a colony, so a new Java tool,
       `ColonyGameMaker`, makes one game, kept in `Tests/JavaOracle/games`
       (88 KB). It generates a game from a fixed seed, founds three
       colonies (1, 4 and 8 colonists of varied types) for each European
       player, adds schools, build queues, a missionary, a soldier and
       pioneers, and plays 3 server turns.
     - `MapOracle` gained sections for colonies (every work location
       with its production, every value of the colony's own), native
       settlements, and the rules of every unit: about 30 values, its
       move type and cost to each neighbour, and its move type to every
       settlement and every unit on the map, from its own tile and from
       the water next to the target.
     - A last section sets peace and contact between everyone (with two
       Europeans at war) and loads one ship. Without it, scouting,
       learning, missions and trade were never reached, as no one had
       met the natives.
     - All values match Java for all 25 inputs. The full dumps are now
       716 KB zipped.
     - 97 tests pass in 85 seconds; all 25 inputs take 4 minutes in a
       release build; the package builds for the iOS Simulator.
     - Deliberate bugs: the rounding of part moves fails on all three
       detailed inputs, and dropping the war check on trade fails on the
       colony game. Dropping a tile's sight bonus goes unnoticed, because
       no tile type in the bundled rules has one (only the scout role and
       de Soto do).
8. **Players and economy:** `Player` (4.6k), `Europe`, `Market`,
   `Monarch`, `HighSeas`, `TradeRoute`, `NativeTrade`.

   **Status: done.** Every part of a saved player is read (apart from
   messages and history), and what Java computes about players, their
   markets, monarchs, Europe and trade matches.

   - **Ported (`FreeColCore`, about 4,000 lines):**
     - `Player` in full (`Player.swift`, `PlayerRules.swift`): state
       and reading; units in Java's `HashSet` order; the next-unit
       iterators (`UnitIterator`); migration, liberty, founding
       fathers and the Thomas Paine bells bonus; taxes, boycotts and
       trade; prices in Europe; trade routes; settlements; stances,
       tension and contact; claims; and the AI's colony site values.
     - `Market`, `MarketData` and `LastSale`.
     - `Monarch` with its actions, taxes, REF growth, support and
       mercenaries, and `Force`.
     - `Europe` in full: recruits, unit prices, recruit price,
       immigration, goods prices and trade.
     - `TradeRoute`, `TradeRouteStop` and the `TradeLocation` protocol
       (colonies, native settlements, Europe). Units follow routes and
       stops.
     - `NativeTrade`, `NativeTradeItem`, `GoodsTradeItem` and
       `TradeItem`.
     - Game setup: `NationOptions` and the map editor's `Area`s.
     - **Left from earlier steps:** pricing and equipping at a location
       (`priceGoods`, `equipForRole`); `evaluateFor` for goods, units,
       work locations and colonies; build prices; and tile potential
       ordered by market price (`Valuation.swift`).
   - **Not yet ported:**
     - Strength (`calculateStrength`, the monarch's war support) needs
       the combat model (step 9).
     - Messages, history and election turns (step 10).
     - Names (`NameCache`) and labels.
     - The diplomatic trade items (colonies, gold, stances, units,
       incitement) come with diplomacy in Phase 3.
     - Players' views of tiles (`cachedTile`) and visibility (`canSee`,
       `getVisibleTileSet`) are server state: Java keeps cached tiles
       only in a server game, and the server overrides `hasExplored`.
       They move to Phase 3 and are still skipped when reading.
   - **Java behaviour mirrored:**
     - **The unit set:** `getUnitSet` copies the `HashSet`, which can
       reorder it, so Swift returns the units in the copy's order. Unit
       hashes are Java's (`31 × id hash + game id hash`).
     - **`DoubleStream.sum`:** compensated (Kahan) summation, as Java
       uses for strengths.
     - **Shared AbstractUnits:** the rules' unit lists are handed out
       uncopied, so forces built from them (mercenaries) change the
       rules' own numbers. Swift's `AbstractUnit` is a class, so it does
       the same.
     - **`maxBy`/`minBy`:** keep the first of equal values.
     - **Int wraparound:** an undefined mercenary price times two units
       is 0.
     - **Rounding:** `amount × weight` is float arithmetic, and
       products are rounded left to right (`v × 0.67 × development`).
   - **Not compiled in Java:** `getOutpostValue` sits inside a comment
     whose javadoc is never closed, so it isn't part of FreeCol and
     isn't ported. The compiled class (`javap`) is the list of what
     exists.
   - **Tests:**
     - A new Java tool, `EconomyGameMaker`, loads the colony game and
       adds what only comes later in a game: trade routes with ships
       following them, last sales, offered and current fathers, a
       raised unit price, trade and a boycott, Thomas Paine and a tax,
       gold, a privateer attack and a mission ban. It moves the turn to
       60, when the monarch starts to act. The result is kept with the
       tests (89 KB) as a fourth detailed input.
     - `MapOracle` gained three sections:
       - **players:** about 40 values each, including the unit set's
         order, the next active units, trade, prices, relations, ports,
         claimable tiles, the colony site value of every third land
         tile, Europe, the market data and its order, the monarch's
         forces, actions, choices, taxes and seeded random offers, and
         the tax limits.
       - **setup:** the nation options and areas.
       - **economy** (after everyone has met): trading in every market
         and raising the tax; a trade route made, verified, followed and
         removed for each European; and a native trade session between
         a loaded ship and every native settlement.
       Colonies, work locations and units also record their values and
       routes.
     - All values match Java for all 26 inputs. The full dumps are now
       1.2 MB zipped.
     - 97 tests pass in 2 minutes. All 26 inputs take under 4 minutes
       in a release build. The package builds for the iOS Simulator.
     - **Deliberate bugs:**
       - dropping the price limit on New World goods fails 32 checks on
         each saved game;
       - using the unit set without the copy's reordering fails 9 or 10
         per input;
       - a bells bonus ignoring the tax fails on the economy game.
       Changing the monarch's lower-tax threshold was missed until the
       oracle gained the tax limit checks; now it fails 3.
9. **Combat and pathfinding:** `SimpleCombatModel`, `PathNode`,
   `CostDecider`, the A\* search in `Map`, `GoalDecider`.

   **Status: done.** Combat odds, powers, modifiers and results, and
   every path and search the oracle asks for, match Java.

   - **Ported (`FreeColCore`, about 2,800 lines):**
     - **Combat (`CombatModel.swift`):** `CombatModel`,
       `SimpleCombatModel` (offence and defence power, offensive and
       defensive modifiers for land, naval, settlement and bombard
       combat, and attack results with `resolveAttack`), and
       `HitpointsCombatModel`, which only the `hitpoints` mod uses.
     - **Path finding (`Pathfinding.swift`, `MapSearch.swift`):**
       - `PathNode`;
       - the cost deciders (base, tile cost, legal tiles, avoiding
         settlements, blocking units and naval danger, and composed);
       - the goal deciders, including `MultipleAdjacentDecider`;
       - the A\* `searchMap`, `findPath` (Europe and tiles, with or
         without a carrier), `search`, `searchCircle` and the best entry
         tile.
     - **Unit (`UnitPaths.swift`):** paths and turns to reach;
       - the nearest settlement, port and intermediate port;
       - the trivial path and the path start;
       - resolving a destination at sea, the repair location;
       - searching for danger;
       - combat modifiers and ranged attacks.
     - **Left from earlier steps (`Defence.swift`):**
       - the defending unit of tiles, colonies and native settlements;
       - colony defence power, ratio and how well defended;
       - plunder ranges and amounts;
       - tile safety (dangerous to ships, safest and safe tiles,
         blocked);
       - player strength and the REF strength ratio;
       - the monarch's war support;
       - players' visibility (`canSee`, cached until invalidated as in
         Java, `getVisibleTileSet`, `canSeeUnit`).
     - **Explored tiles:** Java's server keeps each player's cached
       copy of each tile. Swift now records which players have one
       (`Tile.isExploredBy`), which the high seas search and visibility
       need. The copies themselves are still skipped (Phase 3).
   - **Not yet ported:**
     - `serverAvoidIllegal` and the stealthy goal decider (server and
       AI, Phases 3 and 4);
     - search tracing.
   - **Java behaviour mirrored:**
     - **Java's `PriorityQueue`:** the binary heap is ported exactly
       (offer, poll, removal from the middle), as it decides between
       equal-cost nodes and so which path is found.
     - **Modifier indexes changed in place:**
       - `getCombatModifiers` gives the unit type's, owner's and role's
         modifiers their combat indexes;
       - the compatibility fix gives default-index modifiers the general
         index;
       - both change the rules' own modifiers, and the shared "unknown
         defence" modifier.
     - **The composed cost decider** never resets its highest cost.
     - **Tiles have no modifiers of their own**, so the ambush bonus
       adds nothing.
     - **Nation types** now answer the `isIndian`, `isEuropean` and
       `isREF` scope methods. Without them, the Cortes-style offence
       bonus against natives never applied.
   - **Path nodes:** the link back is weak, as two strong links would
     never be freed. A path is held by its first node, and a search
     keeps every node it makes until it ends, so replaced nodes still
     link back as in Java.
   - **Speed:** in a release build, Swift's searches are now within
     about 2× of Java. The changes:
     - the search keys its maps by object rather than string id;
     - feature lookups no longer rebuild sets (closer to Java too);
     - lookups by id alone are memoised until the features change;
     - `initialMovesLeft` is cached for the length of a search.
   - **Tests:**
     - `MapOracle` gained four sections:
       - **paths:** about 15 per European unit: to each colony, Europe
         and the entry tile; carried, and from aboard a ship; nearest
         settlement and port; the trivial and intermediate paths;
         repair; entry tiles; danger. Also paths for some native units,
         and tile searches for every input.
       - **combat:** each unit's measured offence and defence; attacks
         within three tiles with odds, powers, modifiers and seeded
         results from both models; bombardment; duels between one unit
         of each owner, type and role and every foreign one; colony and
         settlement defence and plunder; player strength, war support
         and tile safety.
       - **visibility:** explored and visible tiles, and what each
         player can see.
     - The economy game now also has a drydock in one colony and a
       colonist aboard a ship, so repairs and carried paths are
       reached.
     - All values match Java for all 26 inputs. The full dumps are
       1.2 MB zipped.
     - 97 tests pass in 4.5 minutes in a debug build (the detailed
       comparison takes 3.5 of them). All 26 inputs take 5.5 minutes in
       a release build. The package builds for the iOS Simulator.
     - **Deliberate bugs:**
       - Java's heap tie order: fails 512 checks.
       - Dropping the land attack bonus: fails 1,971.
       - Ignoring repair colonies: missed until the drydock was added;
         now fails.
       - Two can't be reached by any save:
         - the extra cost of unexplored tiles: a server game's tiles are
           all explored, so only client paths use it;
         - the turn spent disembarking before walking inland: every
           colony is coastal, so carried units sail into them.
     - The duels reach captured colonies, damaged ships, promotions,
       evasions and lost or captured equipment. Natives rarely win, so
       pillage, demotion and destroyed settlements are not reached.
10. **`StringTemplate`, `ModelMessage`, and the `.properties` loader:**
    Java's escaping rules plus FreeCol's `{{plural:…}}` and `{{tag:…}}`
    syntax.

    **Status: done.** Every message in all 60 bundled languages, every
    template rendered with sample numbers, and the labels, history and
    messages of a saved game match Java.

    - **Ported (`FreeColCore`, about 2,300 lines):**
      - **The loader** (`MessageBundle`). FreeCol's message files are
        not `java.util.Properties`; Java reads them line by line:
        - a line starting with `#` is a comment;
        - the key is the trimmed text before the first `=`, and the
          value the trimmed rest;
        - `\n` and `\t` are the only escapes;
        - lines end at `\n`, `\r` or `\r\n`, and nothing continues a
          line.
        Files load in Java's order: the default, the language, the
        country and the variant, from `data/strings`, then from each
        rule set with a mod descriptor and specification (classic,
        freecol).
      - **`Messages`:**
        - `message` for keys and the four template types;
        - Java's `replaceChoices` and `getChoice`, ported on UTF-16 code
          units so indexes and substrings behave as in Java;
        - the key helpers;
        - `getUnitLabel`;
        - the season names, from NameCache.
      - **Plural rules (`NumberRules.swift`):** the CLDR data, `Rule`
        and `Relation` (`is`, `in`, `within`, `mod`, `not`), the simple
        rule classes, and Java's `Double.parseDouble` for selectors.
      - **`StringTemplate`, `ModelMessage` and `HistoryEvent`:** with
        reading, Java's `toString` and `hashCode` (the message's text
        includes it), and the @compat 0.11 forms.
      - **Labels (`Labels.swift`):** about 60 label methods, covering
        units (plain, national and full), players, tiles, regions,
        settlements, work locations, goods, abstract units, turns,
        trade routes, location labels (also as a player sees them),
        and combat odds.
      - **Player:** history and messages are now read (they were skipped
        before), with election turns, the start game, emigration and
        price change messages.
    - **Not yet ported:**
      - NameCache's name generation (settlements, regions, ships,
        mercenary leaders), which the server uses (Phase 3).
      - Mod message files, and the client's message filtering by
        option (Phase 5).
    - **Java behaviour mirrored:**
      - **French has no plurals in FreeCol:** its CLDR rule ("n within
        0..2 and n is not 2") is neither of the two simple forms Java
        recognises, so Java stores nothing for it.
      - **`Rule.toString`** runs "or" conditions together. Only single
        conditions are ever compared, but it is mirrored.
      - **Season names are cached** from the first language that asks
        for them. Java then shows English seasons in Russian if English
        was loaded first.
      - **`StringTemplate.copy` shares the list of pairs** with the
        original.
      - **A template's `toString`** runs its pairs together with no
        separator.
    - **Tests:**
      - A new Java tool, `I18nOracle`, records for each language:
        - its loaded messages;
        - each key's message;
        - each key with placeholders or choices rendered as a template,
          with every placeholder set to 0, 1, 2, 5 and 21 (this reaches
          the plural and tag choices);
        - the plural category of 39 selectors, including Java's odd
          number forms (`+3`, ` 4 `, `1e1`, `3f`, `NaN`).
        It also records the economy game's labels, history and
        messages, with their Java forms and hashes, in 7 languages.
      - Full documents for English, German, Russian and Polish are
        zipped in `Tests/JavaOracle/i18n/full.zip` (1.1 MB). All 60
        languages have digests.
      - By default the tests check the four in full, 12 more by digest
        and the labels. `FREECOL_ALL_MAPS=1` checks every language.
      - The economy game now also has history, messages and a named
        missionary.
      - 103 tests in 24 suites pass in about 3.7 minutes in debug.
        In release, all 26 map inputs and all 60 languages take about
        5 minutes. The package builds for the iOS Simulator.
      - **Deliberate bugs:**
        - Bracket matching off by one: the renderer crashes.
        - Dropping the tab escape: 21 differences in each full
          language.
        - Dropping the plural rules' integer check: 1.
        - The message hash without the displayed flag: 28.
        - A wrong separator in named unit labels: missed until the
          economy game got a named unit with a role; now 21.
    - ✅ **Milestone:** loading any of the 10 reference saves in Swift
      produces the same snapshot as Java. Saving it and loading it again in
      Swift also gives an identical snapshot.

### 1e. Tests

- There are 42 model tests in `test/src/net/sf/freecol/common/model/`,
  including `ColonyProductionTest`, `CombatTest`, `ModifierTest`,
  `PathfindingTest` and `SerializationTest`. Port them to Swift Testing
  alongside each step above. Some depend on server-side helper classes,
  so expect a few of them to wait until Phase 3.
- Every reference save becomes a comparison test, and the turn recordings
  get used in Phase 3.

**Status: done.** All 42 test files are ported, one Swift file per Java
file, in a new `FreeColModelTests` target: 271 Swift tests for Java's
272 (MarketTest's two empty tests are left out, and RandomRangeTest's
checks for bad arguments became two exit tests). 254 run and pass; 17
wait for later phases, and one check that fails in Java too is a known
issue.

- **Building games in code.** The Java tests build their games with the
  server's constructors (`ServerGame`, `ServerPlayer`, `ServerUnit`,
  `ServerColony`, `ServerBuilding`, `ServerIndianSettlement`), while the
  Swift model could only be read from saves. The model side of those
  constructors is now in `FreeColCore`, ready for the server in Phase 3:
  - `Player(game:nation:)`: Europe, the high seas, the monarch, the
    market and the nation type's features;
  - `Unit(game:location:owner:type:role:)`: creation changes,
    nationality, role, location and owner;
  - `Colony(game:owner:name:tile:)`: colony tiles, the free buildings
    and the default queues; `Building` and `ColonyTile` initializers;
  - `IndianSettlement(game:owner:name:tile:isCapital:learnableSkill:missionary:)`;
  - `Settlement.placeSettlement`, `exciseSettlement` and `changeOwner`,
    and `Tile.changeOwnership` and `changeOwningSettlement`;
  - `Game.addPlayer` (which now takes the nation out of the nation
    options, as in Java), `changeMap`, `canAddNewPlayer` and
    `sortPlayers`;
  - disposal of units and settlements (Java's `getDisposables` and
    `disposeResources`).
- **Also ported, because tests use them:**
  `BuildingType.potentialProduction`, `WorkLocation.setWorkFor`,
  `Settlement.canImproveUnitMilitaryRole`,
  `IndianSettlement.tradeGoodsWithSettlement`, `Role.availableRoles`,
  `FoundingFather.isAvailableTo`, the specification's option setters
  and `applyDifficultyLevel(id)`, `removeScope` and `copyScopes` on
  types, unit type changes made in code, and
  `Specification(resolved:source:)` for documents that extend a rule
  set.
- **Fixes found on the way:**
  - `Tile.changeType` did not update the colony working the tile.
  - Scopes asked players for `getNationID` rather than Java's
    `getNationId` (only an XML comment in the rules uses the wrong
    name, so no game was affected).
  - Unit types did not answer scope methods such as `getLineOfSight`,
    which Java finds by reflection.
- **The test helpers** (`FreeColTestCase.swift`) mirror Java's
  `getStandardGame`, `getTestMap`, `getCoastTestMap`,
  `getStandardColony`, `MapBuilder`, `ColonyBuilder` and
  `IndianSettlementBuilder`. Java shares one specification between all
  tests; here each suite loads its own and runs its tests in turn, as
  suites run in parallel. Game objects refer to their game weakly, so
  the helpers keep every test game alive; otherwise a test that only
  holds a map or colony loses the game (at once in an optimized build).
- **Running the Java tests** shows what Java itself does. Java's
  `AllTests` passes 268 tests but leaves out `PathfindingTest`, which
  fails in Java: its last check expects a colony where Java (and Swift,
  on the same tile) finds the native settlement. That check is a known
  issue here.
- **Waiting for later phases (disabled, with the reason):**
  - writing XML: `SerializationTest` (also needs an XML Schema
    validator), `MonarchTest.serialize`, `BuildingTest.serialize`, and
    the copies that go through XML (`copyColony`, `Unit.copy`,
    `Map.copy`, `Tile.copy`);
  - the server (Phase 3): `CombatTest.regulars` and `captureConvert`
    (`csCombat`), `IndividualFatherTest.deLasCasas`
    (`csAddFoundingFather`), `HighScoreTest`.
- **Differences in form only:**
  - Java's `equals` and `hashCode` on templates are `javaEquals` and
    `javaHash`.
  - Java's exceptions for bad arguments are preconditions here, checked
    with exit tests.
  - Tensions are values, so a change is written back.
  - Some loops over Java's repeated assertions are folded together.
- All 374 tests in 65 suites pass in about 4.6 minutes in debug (the
  model tests alone take 15 seconds), and the package builds for the
  iOS Simulator.
- **Deliberate bugs**, each caught:
  - settlements claiming only their own tile: 6 tests, 102 failures;
  - `Tile.changeType` not updating the colony: 2 tests;
  - unit types not answering `getLineOfSight`: 3 tests;
  - new players without their nation type's features: at least 8
    tests.

**Exit criteria:** the engine loads the rules and real saves, answers the
same questions as Java (production, combat odds, paths, prices), and
passes the ported tests.

## Phase 2: Load the game's data files

- Port `common/resources` and `common/io` with resource mappings (the
  `data/base` `.properties` files) so the engine can find images, sounds
  and fonts.
- Prepare the 215 MB of `data/` for iOS: put images in asset catalogs or
  keep the folder structure, drop the formats iOS can't use, and look at
  shrinking the images.
- Small phase, but the UI depends on it.

**Status: done.** The merged resource mapping in all 61 languages, every
mod's mapping, and Java's decoding of colours, fonts, the animated font,
the animations and properties files match Java. `swift/scripts/prepare-ios-data.sh`
makes an iOS copy of `data/` (160 MB, or 89 MB without the extra image
sizes, from 215 MB).

- **Ported, in a new `FreeColResources` module** (`common/resources`
  and `common/io/sza`):
  - the resource kinds (colour, font, string, animated font, animation,
    sound, video, image), with Java's caching keys and locators;
  - `ResourceFactory`, which picks the kind from the URI and key and
    makes one resource per URI;
  - `ResourceMapping`, with its key prefixes, `resource:` aliases and
    layering;
  - `ResourceManager`: data/base, the total conversion (data/default
    and its parents), mods and the saved game, each replacing keys of
    the ones before;
  - the loader (`FreeColDataFile.getResourceMapping`): the resource
    files for the language, keys ending ".r0", and each image's other
    sizes (`name.size2.png`) and variations (`name1.png`), found by
    listing its directory and sorted as Java sorts paths;
  - Java's `Color` names and hex values, `Font.decode`, `FAFile` (the
    signatures on the declaration of independence),
    `SimpleZippedAnimation` and `PropertyList`.
  - Resources describe and parse but do not decode images or sounds;
    that is for the UI. Animation frames keep their image data, with
    the size read from the PNG or JPEG header.
- **Also ported:** `java.util.Properties.load` (`FreeColUtil/JavaProperties`),
  which the resource files use, unlike the message files: ISO 8859-1,
  `=`, `:` or white space between key and value, continued lines and
  `\u` escapes. `FreeColDataFile` and `JavaURI` (FreeColIO) write file
  URIs as Java's `File.toURI` and `Path.toUri` do, since those are the
  caching keys.
- **Differences:**
  - Java drops sounds it can not decode; here a sound file only has to
    exist.
  - Java fails on an image name without a dot or in a directory it can
    not list, and on a ".r0" alias; here those are skipped. The bundled
    data has none.
  - Zipped data files (Java reads them as jars) are not supported; the
    bundled data and mods are directories.
- **Unicode:** paths are kept as strings, never read back from a `URL`,
  whose path decomposes accented letters. Some string resources hold
  precomposed Greek letters, which only the digests caught: Swift
  strings compare equal under canonical equivalence, but their bytes
  differ.
- **Tests:**
  - A new Java tool, `ResourceOracle`, records the merged mapping of
    each language (every key's kind, caching key, locator, colour, font,
    string, sound files, image sizes and variations), each mod's
    mapping, colour and font names, the animated font's letters and
    names with their points, every animation's frames, and how
    `java.util.Properties` reads eleven tricky documents. English and
    Russian are written in full (zipped, 110 KB), every language as a
    digest.
  - By default six other languages are checked by digest;
    `FREECOL_ALL_MAPS=1` checks all 61 (about a minute).
  - The 15 tests take 10 seconds. All 389 tests in 66 suites pass in
    about 4.4 minutes in debug, and the package builds for the iOS
    Simulator.
  - **Deliberate bugs**, each caught:
    - not dropping a variation's trailing digits: 3 failures;
    - alpha for colours of exactly eight characters: 7;
    - no continued lines in properties files: 2;
    - no `resource:` aliases resolved: 4.
- **Preparing `data/` for iOS** (`swift/scripts/prepare-ios-data.sh`,
  into `build/ios-data`):
  - **Folders, not asset catalogs.** The mappings name files by path,
    variations and sizes are found by listing directories, and mods add
    files of their own; an asset catalog allows none of these.
  - **Sound:** iOS plays neither Ogg Vorbis nor Theora. The 38 Ogg
    sounds become AAC with macOS's `afconvert`, which decodes Vorbis on
    macOS 15: music at 160 kbit/s (it was about 430), other sounds at
    128. Music drops from 86 to 39 MB. The mappings still name the
    `.ogg` files, so caching keys stay Java's; `IOSFormats` makes the
    sound and video resources read the converted files.
  - **Video:** the opening video becomes MPEG-4 if ffmpeg is installed,
    and is left out otherwise (it is here).
  - **Images** stay PNG (87 MB). Of the 97 MB of PNGs, 69 are the
    other sizes Java loads with 2 GB of memory or more. iPhone screens
    probably want them, so they are kept unless `NO_SIZES=1` is given,
    which goes with loading the resources with `highQuality: false`.
    No lossless PNG optimiser is installed; one (such as oxipng) could
    shrink them further.
  - `modsNotWorking`, READMEs and `.DS_Store` files are left out.
  - A test checks the prepared data maps the same keys as `data/`, with
    every sound playable, when it has been made.

## Phase 3: Turn processing without a separate server (~45k lines of server code, without the AI)

- Port `server/model` (`ServerPlayer`, `ServerUnit`, `ServerColony`, …)
  and `server/control` (`InGameController`, `ChangeSet`).
- **Drop the network layer.** FreeCol currently runs its own server even
  in single-player and sends ~19k lines' worth of protocol messages.
  Instead:
  - Player actions become typed Swift commands, such as
    `moveUnit(id, direction)`.
  - `ChangeSet` becomes a list of change events that the UI observes.
  - Keep the boundary between engine and UI strict, so multiplayer could
    be added back later.
- Port `server/generator` (map and game generation).
- Run the engine off the main thread (a Swift `actor`), with the UI
  reading snapshots.
- ✅ **Milestone:** with the same seed, the recorded turns match the Java
  recordings turn by turn, for N turns with only computer-controlled
  players.

### 3a. Size and how it is checked

Without the AI and the networking, the server is about 18,000 lines:
`server/model` (10k, with `ServerPlayer` at 4.7k), `server/control`
(4.3k, nearly all `InGameController`), `server/generator` (3.3k), and
`ChangeSet` (1.6k, in common/networking).

The recorded turns (`TurnRecorder`) are the check. The recorder makes a
seeded game and advances it with the server's own new-turn processing
(`csNextTurn` and `csNewTurn`), without player moves, so it needs no AI.
Each turn is dumped as the saved game's XML tree, and the saves hold the
server's random state. So the Swift engine reads Java's turn N, runs the
same processing with the same random numbers, writes the game as XML,
and must give Java's turn N+1. That needs the model to write XML first.
The milestone's turns with computer players need the AI, so they came
with Phase 4 (step 4 has them: sixty rounds of two new games).

### 3b. Port order

1. **Writing XML:** `FreeColXMLWriter` with its write scopes (save,
   server, and one player's client view), each model and specification
   class's `writeAttributes` and `writeChildren` (about 2,000 lines),
   and the players' cached copies of tiles, which saved games hold and
   the Swift model so far only noted. Checked by writing every input
   game and specification and comparing the XML trees with Java's.
   Saving games needs it too.

   **Status: done.** Every bundled map and saved game writes the same
   XML as Java, for a saved game and for each European player's view,
   with its specification; so do the three rule sets loaded from
   data/rules.
   - **Ported:** `FreeColXMLWriter` and its write scopes (FreeColXML);
     `toXML`, `writeAttributes`, `writeChildren` and `serialize` for
     every game and specification class, in each class's file, and the
     options; `FreeColObject.copy`, `Tile.getTileToCache` and
     `cacheUnseen`; Java's no-intern read scope, so the copies a saved
     game holds are read without registering them, referring to each
     other and to the originals.
   - **Players' views:** each tile keeps each European player's view
     (the tile itself, or a copy of what the player last saw) and what
     the player knows of a native settlement there, replacing the set
     of players who had explored it. A view of a tile with a native
     settlement is saved as a copy even when it is the tile itself, as
     in Java, which writes the tile for that player.
   - **Java behaviour kept, as the oracle shows it:**
     - writing a player's view of another player adds that player's
       tension towards the viewer to the save (getTension stores what
       it makes);
     - working out what a player can see (with fog of war) refreshes
       its views of the tiles it sees, and the save does that part way
       through when it writes a copied view, so a stale view of a tile
       the player can now see is replaced;
     - `canSee` goes by map position, so a copy of a tile counts as
       the tile;
     - a type's own scopes are sorted by `Scope.hashCode` when written;
       required abilities, allowed workers, tile type changes,
       starting units and the founding fathers are written in Java's
       HashMap or HashSet order, so the Swift model keeps those as
       `JavaHashMap`s. Rules read back from written XML can order the
       European starting units differently from the rules they came
       from (copied maps are smaller HashMaps), in Java as here;
     - reading written rules again makes the custom difficulty's
       groups uneditable, in Java as here.
   - **Checked:** `XmlOracle.java` writes the trees (as `XmlTree`
     makes them: attribute order and the order of abilities and
     modifiers do not matter) of four inputs in full and digests of
     all 26, plus the colony game after each player is given a stale
     copy of every settlement tile; Tests/JavaOracle/xml holds them.
     `XMLWritingTests` compares the whole trees, the digests (two maps
     by default, all with FREECOL_ALL_MAPS=1), the stale copies, and a
     saved game read back and written again; `SpecificationWritingTests`
     compares the rule sets with spec-*.xml. Five deliberate bugs were
     each caught: a modifier attribute renamed, copied views written
     in the save scope, the tension side effect left out, copies
     registered when read, and the contact level left out for
     uncontacted players.
2. **The change set:** `ChangeSet` as a list of changes that the UI will
   observe, without the messages, and the server's `See` visibility
   rules.

   **Status: done.** Each player is told what Java tells it, in the
   same order, for every kind of change, and the game is left as Java
   leaves it.
   - **Ported, in a new `FreeColServer` module:** `ChangeSet` with `See`
     and every kind of change (attack, attribute, feature, message,
     move, object, partial, players, remove, spy, stance), the helpers
     with their side effects (abilities, modifiers, history and sales
     are added to the game), and `build(player)`. It gives a
     `PlayerUpdate`: the messages as `PlayerChange` values the UI can
     observe (by priority, keeping the order added; updates merged, and
     feature changes for the same object), plus the settings gathered
     from attribute changes. A `PlayerUpdate` can be written as Java's
     message XML, which is how it is checked. Messages the server's
     code adds itself (new turn and so on) conform to `ServerMessage`
     and are ported as the later steps need them.
   - **Also ported:** `Unit.reduceVisibility` and copying an object as
     a player sees it (`copy(for:)`).
   - **Java behaviour kept:** working out whether a player is told
     asks what it can see, which (with fog of war) refreshes its views;
     move animations are never sent to AI players; a lone message gets
     the update's settings added to its own attributes
     (MultipleMessage.simplify); `addMessage` does not add the message
     to the player.
   - **Checked:** `ChangeOracle.java` reads the colony game, makes its
     first European player human, and records what each of the 12
     live players is told of 19 change sets covering every kind of
     change and visibility rule, including a colony another player can
     see and a unit moving out of sight, and a digest of the game
     after them all (Tests/JavaOracle/changes.json). `ChangeSetTests`
     makes the same change sets and compares the message trees and the
     digest, and checks `See` and server messages directly. Eight
     deliberate bugs were each caught.
3. **A colony's new turn** (`ServerColony.csNewTurn`, `ServerBuilding`,
   `ServerColonyTile`): production, storage, growth, building, liberty
   and education. Checked against recordings of the colonies and
   economy games.

   **Status: done.** Eight rounds of every colony's new turn and
   warnings give the same game, the same messages for every player and
   the same random numbers as Java.
   - **Ported** (in FreeColServer, as extensions of the model's
     classes, since the Swift model has no server subclasses):
     `ServerColony.csNewTurn` and `csNewTurnWarnings` with building
     (new buildings, upgrades with ejected units, units, colonists
     born), production with starvation and famine warnings, the build
     queues' completion actions, custom house exports, free buildings,
     rebels and government messages, teaching and repairs;
     `ServerBuilding` (teaching, repairs, missing input warnings);
     `ServerColonyTile` (resources running out); and the parts of
     `ServerPlayer` and `ServerUnit` these use: selling in Europe and
     spreading trade to the other markets, disposing of a settlement
     and reassigning its tiles, removing and repairing units.
   - **Also:** `ServerGame`, which issues identifiers, and
     `readServerGame` to load a game into one; `checkBuildQueueIntegrity`
     (keeping Java's habit of not checking the item after one it
     drops), `checkForGovMgtChangeMessage`; buildings are `Named`;
     `Messages.scopedBundle`, a task-local message bundle, so a test
     that needs English text is not upset by tests in other languages
     running at the same time.
   - **Not yet ported**, and reported by a `NotYetPorted` error: ship
     names (NameCache), so a colony can not build a ship yet, and
     disposing of a native settlement with a missionary.
   - **Checked:** `ColonyTurnGameMaker.java` makes a game, from the
     colony game, whose colonies are about to build a building, an
     upgrade and artillery (alone in its queue, so built again), have a
     colonist born, train a student, export with a tax, use up a
     resource on a tile another player has seen, and repair a ship,
     with an elder statesman, an empty queue and colonies that starve.
     `ColonyTurnOracle.java` records eight rounds of the colonies'
     turns, in ServerPlayer's order, from a seeded generator
     (Tests/JavaOracle/colony-turns.zip); `ColonyTurnTests` compares
     each round's save tree, messages and generator state. Eight
     deliberate bugs were each caught, three only after the game was
     made to reach them. The rebels' message is not reached: Java
     updates the old rebel percentage as liberty arrives, so the turn's
     own check only sees a change when the colony's size changes too.
4. **The rest of the new turn:** units (moves, improvements, repairs),
   native settlements, Europe and the market, the monarch's raises, and
   `ServerPlayer.csNewTurn`. Checked against `TurnRecorder`'s turns.

   **Status: done.** Everything `ServerGame.csNextTurn` and `csNewTurn`
   reach is ported, and plays as Java does: TurnRecorder's game from its
   first save to turns 5 and 10, and a prepared game for six turns,
   turn by turn, with the same game, messages and random numbers.
   - **Ported** (FreeColServer): `ServerGame.csNextTurn` and
     `csNewTurn` (with whether the Spanish succession is due);
     `ServerPlayer.csNewTurn` (settlements, units, Europe, rebels,
     emigration, upkeep and bankruptcy, natural disasters with all
     their effects, colony warnings, stance reports), `csEmigrate`,
     `csApplyDisaster`, `csDamageBuilding`, `csDamageShip`,
     `csSinkShip`; `ServerIndianSettlement.csNewTurn` (production,
     births, horses, wanted goods); `ServerUnit.csNewTurn` (attrition,
     promotion by experience, moves, improvements and `csImproveTile`,
     fortifying, arriving in Europe); `ServerEurope` (repairs and
     recruits); `ServerColony.destroyBuilding`; the new turn message.
   - **Moved to step 5, as Java does them when a player's turn starts
     (`csStartTurn`) rather than in the new turn:** the market's yearly
     changes and the monarch's actions. TurnRecorder does not run them.
   - **Not yet ported**, reported by `NotYetPorted`: a unit reaching
     America from the high seas (`csMove`, step 6), the Spanish
     succession itself (only whether it is due), the intervention force,
     and Fountain of Youth recruits. Diplomatic sessions have nothing
     to complete until player actions make them.
   - **Model fixes found on the way:** a goods container empties when
     disposed of, as in Java; a settlement's owned tiles come in the
     order of Java's copy of its HashSet, hashed as game objects are
     (`31 * id hash + game hash`).
   - **Checked:** TurnRecorder's saves at turns 0, 5 and 10 are kept
     with the tests; `NewTurnTests` plays the ten turns and compares
     the saves and generator states. `NewTurnGameMaker.java` makes a
     game from the colony turn game with disasters every turn and
     upkeep (and a broke player), pioneers finishing a road and a change
     of terrain, units fortifying and skipping, a ship reaching Europe
     and a damaged one there, a convert dying of attrition, a native
     settlement with food for a birth and horses to breed, a missionary,
     an emigrant, and the year 1620; `NewTurnOracle.java` records six
     turns (Tests/JavaOracle/new-turns.zip), which `NewTurnTests`
     compares turn by turn. Eleven deliberate bugs were planted; ten
     were caught. The one not caught is in a branch the bundled rules
     never reach (timed modifiers on a player, which bankruptcy's
     modifiers are not).
5. **The turn cycle** (`InGameController.endTurn`): ending and starting
   turns, deaths and withdrawals, the monarch's actions, and the REF.

   **Status: done, apart from the REF.** Ending a player's turn and
   going on to the next plays as in Java: every player is sent the same
   changes in the same order, the reply is the same, and so are the game
   and the random numbers, call after call through new turns.
   - **Ported** (FreeColServer):
     - `InGameController`, with `endTurn` and `csMonarchAction` (every
       action). It runs without a network: `isConnected` says which
       players are sent changes, and `deliver` receives them.
       `setMonarchAction` forces an action, as Java's debug hook does.
     - ServerPlayer's `checkForDeath`, `csWithdraw` and `csKill`,
       `csEndTurn` (free buildings), and `csStartTurn` (for Europeans:
       the market's yearly changes, a founding father joining with all
       its events, the fathers offered, the score; for natives: alarm,
       tension, its messages and conversions).
     - The rest of ServerPlayer this needs: `csChangeStance`,
       `csModifyTension`, `csSetTax`, `csRaiseTax`, `ignoreTax`,
       `csMercenaries`, `createUnits`, `loadShips`, `csChangeOwner`,
       exploring, and `csFlushMarket`.
     - ServerIndianSettlement's `csStartTurn`, alarm changes,
       `csCheckTension`, `csChangeMissionary` and `csKillMissionary`.
       Disposing of a settlement with a mission now works.
     - ServerColony's `csFreeBuilding` and `csAddConvert`.
     - Monarch sessions (`Session`, `MonarchSession`), completed
       unanswered at each new turn.
     - `ServerGame.checkForWinner`, `nextPlayer` and
       `isNextPlayerInNewTurn`.
     - The messages: setCurrentPlayer, setDead, chooseFoundingFather,
       monarchAction and gameEnded.
     - `NameCache`'s ship names and mercenary leaders, kept per server
       game. Colonies can now build ships.
   - **Java order reproduced:**
     - Killing a player removes the other players' units in the order
       of Java's HashMap of game objects. `Game.freeColGameObjectsInJavaOrder`
       gives it: by bucket of a table sized for 10000 objects, then in
       the order registered.
     - Java's HashSets of tiles are emulated (`JavaTileSet`), including
       how each was built. The order of colliding tiles depends on it,
       and an early version that started from a Swift `Set` passed only
       some runs.
   - **Not yet ported**, reported by `NotYetPorted`. None can happen
     before player actions exist:
     - the REF arriving (it needs the REF's AI, Phase 4);
     - granting independence (there is no REF until independence is
       declared, step 6; ported in 6e);
     - forts bombarding ships (`csCombat`, step 6; ported in 6d);
     - a goods party, and accepting mercenaries (both are answers to the
       monarch; ported in 6e);
     - high scores for a human winner.
   - **Checked:** `TurnCycleGameMaker.java` makes three games from the
     new turn game. In each the Dutch are human and start, the Europeans
     have gold and a tax, and each is about to recruit a founding father:
     - monarch: the French and English are at war, the Dutch and Spanish
       at peace. The fathers are La Salle (already joined), John Paul
       Jones, Pocahontas, Coronado and Fugger (with a boycott to lift),
       and a Dutch missionary is about to convert;
     - deaths: a native nation with a Dutch mission dies, the Spanish
       die, and the English have only a ship (so they are given a
       colonist). The fathers are De Soto, and Las Casas with a convert;
     - fathers: Magellan, Brewster, Bolivar and Paine.

     `TurnCycleOracle.java` runs Java's own `endTurn` on them. Every
     player is connected through a connection that records what it is
     sent, so nothing reaches a network or the AI. It records four
     rounds of the monarch game (forcing each monarch action once), two
     of the deaths game and one of the fathers game, 84 calls in all, in
     Tests/JavaOracle/turn-cycles.zip. `TurnCycleTests` compares every
     call. Making the oracle's server first matters: making it fills
     Java's static cities of Cibola from an unseeded generator, which
     the game read afterwards replaces.
   - **Not reached:** the monarch's mercenaries are never offered,
     because under these rules `loadMercenaries` finds none the player
     can buy. The random numbers it uses are still checked.
   - **Planted bugs:** 15 deliberate bugs were planted and 13 were
     caught. The two that passed:
     - comparing tension limits with `<` instead of `<=` changes
       nothing, since equal limits mean the same level, which returns
       earlier;
     - the yearly market change's larger amount for its randomly chosen
       goods type only matters if that type has been traded, which it
       never was in these games.
6. **Player actions as commands:** moving, building colonies, trading,
   combat (`csCombat`), equipping, Europe, founding fathers and
   diplomacy (the sessions), each a typed command.

   Java has about 70 of these. They are ported in five parts:
   - **6a.** Units, colonies, goods, Europe.
   - **6b.** Moving, with exploring, lost city rumours, first contact,
     naming regions, and sailing to and from Europe.
   - **6c.** Dealing with natives: scouting, learning, missions,
     inciting, tribute, gifts, trade and demands.
   - **6d.** Combat, and forts bombarding ships.
   - **6e.** Diplomacy, the answers to the monarch, declaring
     independence, and the REF.

   **6a status: done.** The commands for managing units, colonies and
   goods, Europe and treasure behave as Java's server does. That covers
   what every player is sent, the reply, the game, the random numbers,
   and which commands are refused.
   - **`PlayerCommand`**: a typed command for each of 28 messages. It
     carries identifiers and values as Java's message does, and
     `PlayerCommand(tag:attributes:children:)` reads it from the message
     XML, as a network would.
   - **`InGameController.perform(_:by:)`** checks a command as the
     message's `serverHandler` does, then carries it out as
     InGameController does. A refusal throws `CommandRefused`, where
     Java returns a `clientError`.
   - **The commands:**
     - units: change state, work type and improvement, work, put
       outside, join colony, clear speciality, disband, rename, set
       destination, embark and disembark, assign a teacher, equip for a
       role;
     - colonies: set the build queue and the goods levels, pay for a
       building, claim land (free, bought, or stolen), build a colony
       (European), abandon a colony;
     - goods: load and unload, in a colony or in Europe (buying and
       selling), and pay arrears;
     - Europe and the player: recruit, train, cash in treasure, choose a
       founding father, name the new land.
   - **Also ported:** `NameCache`'s settlement names;
     `buyInEurope`, `csClaimLand`, `csLoseLocation`,
     `updateCurrentFather`, `csSeeNewTiles`, `exploreForSettlement`;
     equipping in Europe (the server's `equipForRole`), in colonies
     and in native settlements; `csEvictUsers`; `csEmbark`;
     `Europe.increasePrice`; `isWorkerAllowed` for tile improvements;
     `Game.settlement(byName:)` and `findFreeColLocation`.
   - **Not yet:**
     - natives building a settlement (a `NotYetPorted` error);
     - the trade route commands, rearranging a colony, naming a region
       (it comes with moving, 6b);
     - chat, game state and the like, which belong to the network
       layer.
   - **Checked:** `CommandGameMaker.java` makes a game from the new turn
     game. The Dutch are human, rich, taxed, owe arrears and have
     fathers on offer. At a Dutch port there are a treasure train, a
     caravel and three colonists outside the colony (one has used some
     of its moves), with a pioneer beside it; a merchantman with furs is
     in Europe; and a colonist stands on open land.

     `CommandOracle.java` has Java's server handle 45 messages through
     each message's own `serverHandler`, with every player connected
     through a recording connection. Four of the messages are meant to
     be refused. Each message is made for the game as it then is, and
     its XML is recorded (Tests/JavaOracle/commands.zip, 125 KB).
     `CommandTests` reads each one into a `PlayerCommand` and compares
     everything per command.
   - **Planted bugs:** 14 were planted. The first try caught only six,
     because the game gave the code nothing to change: no tax, no
     moves or experience to lose, a queue needing only hammers, and a
     unit whose price does not rise. After the game and script were
     strengthened, 12 were caught. The two still passing:
     - leaving out the join command's clearing of moves changes nothing,
       as entering the colony sets a state that clears them, in Java as
       here;
     - disembarking where there are new tiles to see is not reached,
       since everything round the port is already seen.

   **6b status: done.** Moving behaves as Java's server does, and so do
   new turns that bring ships across the high seas.
   - **Commands:** `move`, `moveTo` (to Europe, the map or a settlement,
     turning round if already at sea), `newRegionName` and
     `declineMounds` join `PlayerCommand`.
   - **`Unit.csMove`** ports Java's move:
     - exploring, and the tiles that go out of sight;
     - a first landing naming the new land;
     - every lost city rumour: burial grounds, vanishing, nothing (the
       Mayan years too), learning, a tribal chief, a colonist, mounds,
       ruins, cities of Cibola, the Fountain of Youth;
     - first contact with natives, and native settlements meeting a
       European;
     - natives claiming land near home;
     - waking sentries;
     - units leaving a ship in a colony;
     - being slowed by enemy ships;
     - discovering a region.
   - **Also:**
     - the Fountain of Youth's recruits (chosen by a human, or made for
       an AI);
     - arriving in America from the high seas at the new turn, which
       step 4 left as `NotYetPorted`;
     - `Region.checkDiscover`, `discover` and the server's `csDiscover`;
     - `LostCityRumour.chooseType`;
     - `NameCache`'s new land, region, Cibola and "nothing" names;
     - `csContact` and `csNativeFirstContact`;
     - the newLandName, newRegionName, firstContact and fountainOfYouth
       messages.
   - **Not yet** (`NotYetPorted`, both need diplomacy sessions; both
     ported in 6e):
     - first contact between Europeans;
     - natives offering land at a first landing on it.
   - **Java behaviour kept:**
     - a preset "learn" rumour becomes "nothing" for a unit that can
       learn, as Java's check is the wrong way round;
     - ruins found with mounds can fall through to the burial ground
       case and stay ruins;
     - a city of Cibola with none left becomes ruins, but keeps Cibola's
       message key.
     Java shuffles its extra river names with its global generator,
     which no one can repeat; here they come in order.
   - **Checked:** `MoveGameMaker.java` makes a game from the command
     game, with units beside each thing moving reaches, each with the
     tile to move to as its destination:
     - a first landing;
     - a rumour of each type, and one whose type is chosen;
     - mounds to leave;
     - natives not yet met;
     - an undiscovered region;
     - a French sentry;
     - a French frigate at war;
     - a caravel with a colonist beside the port.

     The game also turns on disembarking in colonies (the FreeCol rules
     turn it off) and still has the seven cities of Cibola to find.

     The command oracle's moves script moves them, names the region,
     recruits from the fountain, refuses a move into water, sails ships
     to the map and to Europe (turning round), and plays four new turns
     for them to arrive, recorded as the turn cycle does. That is 29
     steps, in Tests/JavaOracle/commands.zip with the 6a commands
     (328 KB). `CommandTests.moves` compares every step.
   - **Planted bugs:** 18 were planted. The first run caught 13; the
     game was then made to reach what four of the misses needed (the
     option, the cities of Cibola, the French sentry, an active
     passenger), and 16 are caught. The two still passing:
     - putting the passengers on sentry: the only passenger leaves the
       ship in the colony and becomes active anyway;
     - the Fountain of Youth's count of recruits still to choose: it is
       server state, and only matters after more recruits than the
       script makes.

   **6c status: done.** Dealing with natives behaves as Java's server
   does, from both sides: the European's commands, and the natives'
   answers and demands, which the AI sends in a game.
   - **Commands:** ask about and learn a skill, scout a settlement,
     speak to the chief, establish and denounce missions, incite (asking
     the price, and paying), demand tribute, trade (open, sell, buy,
     gift, close, and every answer the natives can give), deliver a
     gift, the natives' gifts and demands (and the colony's answer), and
     nation summaries.
   - **Also:**
     - the native trade and demand sessions;
     - `csVisit`, `csBuy`, `csSell`, `csGift`, `csCompleteNativeDemand`;
     - `NationSummary`;
     - native trades written as XML;
     - `Unit.adjacentSettlement`;
     - the nationSummary, scoutSpeakToChief, incite, indianDemand and
       nativeTrade messages.
   - **Commands now carry whole objects:** a command can hold a
     `CommandElement`, a small Sendable XML tree for objects a message
     carries whole (goods, a native trade), read into the game when the
     command is carried out.
   - **Java behaviour kept:**
     - every native trade's identifier is empty, and Java's equality
       goes by identifier, so `mergeFrom` between the server's session
       and a trade sent to it does nothing; each side's trade comes from
       the messages it was sent;
     - a demand without a result is "done";
     - enumerated attributes are written in lower case and read in any
       case.
   - **Not yet:** Java also ends a native demand, refused, after a
     timeout in real time. Here only the new turn ends it.
   - **Checked:** `NativeGameMaker.java` makes a game from the command
     game. Dutch units stand by native settlements set up for each case:
     - a settlement teaching expert farming (not a capital, and with no
       Dutch mission, either of which keeps the skill), and a hateful
       one;
     - seven settlements no one has scouted, and a hateful one;
     - one without a mission, and one with a French mission;
     - two to incite against the French;
     - one for tribute;
     - one to trade with, stocked to sell and given goods it wants;
     - one to open a trade with and close it with nothing traded.

     Braves stand by the Dutch port to give and demand, their home
     content with the Dutch.

     The command oracle now writes every message as XML and reads it
     back before handling it, as a server receives it. Its natives
     script plays both sides of trades and demands, each side using the
     trade it was last sent, as a client would. That is 42 steps (four
     refused). `CommandTests.natives` compares every step. The three
     scripts are in Tests/JavaOracle/commands.zip (475 KB).
   - **Planted bugs:** 17 were planted. The first run caught 11. The
     game then gained what five misses needed:
     - a learner's settlement that drops the skill;
     - more scouts, so a chief tells tales;
     - a trade closed with nothing traded;
     - a home settlement with alarm to calm;
     - a trader's settlement with goods to sell.

     After that 15 are caught. The two still passing:
     - the expert missionary's bonus to denouncing, which only matters
       when the random roll lands near the threshold;
     - merging trades the Swift way instead of Java's, which makes no
       difference here, as each side's own trade carries the prices.

   **6d status: done.** Combat behaves as Java's server does.
   - **Commands:** attack, and loot cargo (taking goods a won sea battle
     offers).
   - **Also:**
     - `csCombat`, with every combat result: automatic defence, burning
       missions, capturing (equipment, colonies, converts, units),
       damaging and sinking ships (attacked, bombarded, or in a captured
       colony), demoting and promoting, destroying colonies and
       settlements, ships evading, looting ships, losing equipment,
       pillaging and slaughtering;
     - the stance and tension that follow (privateers only mark their
       victims, Europeans fighting go to war, burning a native capital
       makes the natives surrender), and the winner moving in;
     - `Colony.csChangeOwner`;
     - the loot session and the lootCargo message;
     - forts bombarding enemy ships at the start of a turn (until now
       this stopped as not ported).
   - **Checked:** `CombatGameMaker.java` makes a game from the command
     game. The Dutch are at war with the French and have met the natives
     nearest their port, who are angry with them. Dutch attackers stand
     beside their targets:
     - six veteran soldiers beside French soldiers;
     - a soldier beside an unarmed colonist;
     - two dragoons beside French colonies;
     - a soldier beside a brave;
     - two dragoons beside native settlements, the first left with one
       defender;
     - a frigate beside a merchantman with cargo, and a privateer beside
       a caravel.

     Two armed braves stand beside the Dutch port, which has a fort with
     a French frigate beside it.

     The oracle's combat script attacks with each, loots the cargo it is
     offered, starts the Dutch turn so the fort bombards, plays a new
     turn, and attacks again. That is 28 steps (two refused). Between
     them they demote and capture soldiers, take a brave's equipment,
     slaughter braves, defend a settlement with automatic equipment,
     destroy a native capital (burning its missions, and the natives
     surrender), damage and evade ships, loot cargo,
     capture two colonies and capture units. `CommandTests.combat`
     compares every step. The four scripts are in
     Tests/JavaOracle/commands.zip (544 KB).
   - **Not reached by the game:** sinking ships, natives destroying or
     pillaging a colony, converts and promotion.
     These are ported from Java but not yet compared.
   - **Planted bugs:** 16 were planted and 12 are caught: the captor
     not moving into a colony, plunder, the treasure train, the atrocity
     score, war on natives, moves left after attacking, no loot offered,
     the loot not shown, a captured unit's moves, the attack sound, a
     brave's captured equipment going home, and the bombardment
     message. The four still passing:
     - the defender's tile not marked after a demotion, which other
       changes send anyway here;
     - the tension a native surrender sets, which making peace then
       resets, in Java too;
     - the tension from slaughtering a brave in a settlement, which ends
       at the same value here;
     - a ship's hit points from the combat model, which no result here
       sets (damage is set by the result handlers).

   **6e status: done.** Diplomacy, the answers to the monarch, declaring
   independence and the REF giving up behave as Java's server does. With
   this, step 6 is done.
   - **Commands:** diplomacy (proposing, counter-proposing, accepting
     and rejecting, from a unit or from the colony it deals with),
     answering a first contact with natives, answering the monarch,
     declaring independence, and ending the turn.
   - **Also:**
     - `DiplomaticTrade` and its trade items (gold, stance, colony,
       unit, inciting), read and written as XML;
     - the diplomacy session, `csDiplomacy`, `csAcceptTrade`, and first
       contacts between Europeans (a peace treaty to agree) and at a
       first landing on native land (the land offered);
     - a goods party when a tax raise is refused, and accepting
       mercenaries (or the monarch's displeasure when they can not be
       paid for);
     - `declareIndependence`, with the REF's player made (as an AI
       player that does nothing, until the AI is ported), the
       continental army mustered, a native ally and enemy, and
       mercenaries offered;
     - `csGiveIndependence`, when the REF is defeated at the start of
       its turn;
     - the Spanish succession, which the REF's turns reached
       (`csSpanishSuccession`).
   - **Java behaviour kept:**
     - a session can not be made while a complete one with its key has
       not been looked up since, as Java's constructor checks its map
       directly;
     - finding a contact session finds complete ones too;
     - a new player's `immigrationRequired` is 0 until the pre-game sets
       it.
   - **Not yet:** the REF arriving, which needs the REF's AI (Phase 4).
     Java also ends a diplomacy session, refused, after a timeout in
     real time; here only the new turn ends it.
   - **Checked:** `DiplomacyGameMaker.java` makes a game from the
     command game. The Dutch have not named the new world, are at peace
     with the French, have Jan de Witt, liberty enough to declare
     independence and a tax to raise. The French have gold. The Dutch
     have not met the English, the Spanish or two native nations. Dutch
     units stand ready:
     - a colonist on a caravel beside land of the first native nation;
     - a scout two tiles from a settlement of the second;
     - two soldiers two tiles from an English and a Spanish colonist;
     - two scouts and a soldier beside French colonies, and a
       merchantman with furs beside a coastal one.

     The monarch's expeditionary force is two regulars and a
     man-of-war, so the REF gives up at once.

     The oracle's diplomacy script lands (the land is offered and
     accepted), names the new world, meets the second natives (peace
     refused), meets the English (peace) and the Spanish (no peace),
     negotiates with the French (gold for inciting them against the
     Spanish, with a counter-proposal), buys a colony, demands tribute
     (refused), trades from the merchantman, and answers with no session.
     The monarch raises the tax (accepted), again (refused: a goods
     party), and a third time (ignored until the new turn). The Dutch
     declare (and again, refused), accept the mercenaries offered, and
     end turns until the REF gives independence. That is 48 steps (five
     refused). Java's REF has an AI, which this does not compare; the
     oracle gives Java's server an AI main so it can make the REF,
     records what the REF is sent as it is made, and records it as the
     others after. `CommandTests.diplomacy` compares every step. The
     five scripts are in Tests/JavaOracle/commands.zip (807 KB).
   - **Planted bugs:** 20 were planted and 18 are caught: the
     agreement's version, the gold received, the incited war not shown,
     the traded goods, a unit's moves after a session and after a
     contact, the offered land not given, no mission ban and less
     tension when peace is refused, a wrong answer to the monarch
     accepted, the arrears of a goods party, free mercenaries, the
     declaration's score, the native ally not hating the REF, the REF
     knowing nothing of the map, the units in Europe kept, the
     independent nation still taxed, and units' moves in the Spanish
     succession. The two still passing:
     - reassigning a ceded colony's units, which makes no difference
       for this colony;
     - a larger continental army, as every unit that could change
       already did.

7. **Map and game generation** (`server/generator`): checked by
   generating the same seed as Java.

   **Status: done.** A new game is made as Java's server makes it, and
   from the same seed and options it comes out the same, object for
   object, with the generator left in the same state.
   - **Ported:**
     - `LandMap`, with its four land generators (classic, continent,
       archipelago, islands);
     - `TerrainGenerator`: tile types by latitude, temperature,
       humidity and forest; mountain ranges and hills; rivers (`River`,
       `RiverSection`), with deltas and great rivers; lakes; land
       regions split to at most 75 tiles; fish and resources; the
       style of water tiles;
     - the predefined regions (`ServerRegion.requireFixedRegions`):
       polar, the nine land regions by thirds of the land, and the
       oceans, filled from the edges; `Region` gained the server's
       size and bounds;
     - `SimpleMapGenerator`: native settlement sites, capitals and
       settlements by nation area or region, their land grown, the
       skills taught (and moved so every new world goods type has its
       expert), their goods and braves; lost city rumours;
     - `EuropeanStartingPositionsGenerator`: the starting units, and
       start tiles in each of the three ways (classic, random,
       historical), from map areas or the map's edges;
     - the new game (`ServerGame.newGame`, `startNewGame`, `buildGame`):
       the nation options, the cities of Cibola, the unknown enemy, a
       human player logging in, a player for every other nation, the
       map, the price options (`Specification.generateDynamicOptions`),
       each European's immigration target, gold, recruits and prices
       (`randomizeGame`), and the natives at peace with each other.
   - **Java behaviour kept:**
     - `RandomIntCache` draws with `Random.ints`, which since JDK 17
       takes the low bits of `nextInt()`, not `nextInt(bound)`;
     - `java.awt.Rectangle`'s int arithmetic, which regions rely on
       with widths of Integer.MAX_VALUE;
     - only the polar regions are offered as parents of the new
       regions (`requireFixedRegions` returns the polar and ocean
       regions, not the nine land regions), and those nine are added to
       the map twice;
     - a skill producing nothing (the scout) is weighted by the null
       key of Java's map, which nothing adds to;
     - each AI player Java makes takes a seed from the server's
       generator; here the seed is drawn and kept (`Player.aiSeed`) for
       when the AI is ported. The unknown enemy's is drawn last, as
       Java's AI finds it.
   - **Fixed on the way:** `Settlement.ownedTiles` copied the tiles as
     `new HashMap<>(map)` does, but Java's `getOwnedTiles` is
     `new HashSet<>(set)`, whose table is never smaller than 16, so
     settlements with fewer than 12 tiles listed them in another order.
   - **Not yet:** importing a map, the debug mode's extra units, and
     the AI itself.
   - **Checked:** `MapGenOracle.java` records five maps (one of each
     land generator, hot and cold, two other sizes), made as
     `SimpleMapGenerator.generateMap` begins, each with its land map,
     saved game and generator state. With `--games` it records three
     whole new games for a human Dutch player, made by Java's server
     (`FreeColServer.buildGame`, called directly with a seeded
     generator). The oracle makes Java's static cities of Cibola fresh
     for each, as the server's own unseeded game would otherwise fill
     them first. `MapGenTests.terrain` and `MapGenTests.newGames`
     compare them. The recordings are in Tests/JavaOracle/mapgen.zip
     (452 KB). `-Dmapgen.log=true` prints Java's generation log, and
     `-Dmapgen.save=prefix` saves the games, for finding where Swift
     differs.
   - **Planted bugs:** 23 were planted and 20 are caught, across the
     land generators, terrain types, land regions, hills, rivers and
     deltas, fish, water styles, lakes, ocean filling, rumours,
     settlement growth and skills, starting tiles, native alarm, the AI
     seeds, settlement goods, and the owned tiles' order. The three
     still passing:
     - splitting the land in thirds with > for >=, which only matters
       when a row's total lands exactly on a third;
     - starting passengers left awake, whose saved state comes out the
       same in these games;
     - starting prices not flushed, which only clears the price change
       record, and nothing reads it before the first turn.
8. **The engine actor** and snapshots for the UI.

   **Status: done.** With this, Phase 3 is done; the milestone's turns
   with computer players came with the AI (Phase 4 step 4).
   - **`FreeColEngine`**, a new module above `FreeColServer`, is what
     the user interface uses. `GameEngine` is an actor that owns one
     single-player game:
     - it starts a new game (rules, difficulty, map and game options,
       a seed, the player's name) or loads a saved game, Java's or its
       own;
     - `perform` carries out one of the human player's commands, or
       says why it was refused, changing nothing;
     - `endTurn` plays the other players' turns, through the new turn,
       until it is the human's turn again. Until the AI is ported, the
       computer players end their turns at once;
     - `save` writes a saved game as Java's server does (Java loads it),
       without the AI's objects, which are not ported;
     - `snapshot` describes what the human can see.
   - **Snapshots** are `Sendable` values, so the interface can keep them
     and read them on any thread, and nothing of the live game leaves the
     actor. A `GameSnapshot` has the turn, the players (others' gold
     hidden), the map as the player last saw each tile (unexplored tiles
     blank, units only where it sees them now), the player's units,
     colonies (buildings, work tiles, goods, build queue), the others'
     settlements as last seen (skills once known, alarm), Europe's
     recruits and units, market prices, and the turn's messages,
     translated. Objects are named by identifier and types by their
     specification identifiers.
   - **What happened** comes back with each command and turn as
     `EngineEvent`s: units moving and attacks to show, and messages.
   - **Java behaviour kept:** loading forgets whose turn it was, and the
     first human player takes it, as when it logs in (LoginMessage).
   - **Also:** a zip writer (`ZipArchive.archive`), deflating as Java's
     JarOutputStream does.
   - **Checked:** `GameEngineTests` plays through the actor: a new game
     (the same from the same seed), a ship sailing and a bad command
     refused, turns ended, a game saved and loaded (the same snapshot
     and generator, and the same next turn), one of Java's saved games
     loaded, and snapshots read in another task. A game the engine saved
     loads in Java. Of eight planted bugs, six are caught: others' gold
     shown, computer players never ending their turns, the turn lost on
     loading, moves not shown, the generator not saved, and unexplored
     tiles shown. Units shown on tiles out of sight are not, as none of
     these games has another player's unit out of the player's sight.

## Phase 4: AI (~25k lines)

- **Option A:** port `server/ai` faithfully (`EuropeanAIPlayer`,
  `NativeAIPlayer`, missions, `AIColony`). This is the largest block of
  pure logic, but it's mechanical once the model exists.
- **Option B:** start with a simplified AI so the game is playable sooner,
  then port the full one.
- **Recommendation:** a quick version of B to unblock testing the UI, then
  A. The comparison tests from Phase 3 cover the AI too.

**Chosen: A, a faithful port**, as the user interface was not yet
waiting on it, and a faithful AI makes the Phase 3 milestone (turns with
computer players matching Java's) possible. About 25,200 lines:
`server/ai` (24,300) and `server/ai/military` (900).

### 4a. How the AI is checked

Java's AI runs each turn, and each answer to the server, in a new thread
(`AIPlayer.invoke`), and the AI players answer each other's messages, so
a plain recording would not repeat. Otherwise the AI is deterministic: it
has no clocks and no unseeded generators, and each AI player has its own
generator seeded from the server's when it is made. An AI's requests go
straight to the server's handler and the reply comes straight back, on
the calling thread.

So the AI oracle runs Java's AI with a patched copy of `AIPlayer` (kept
with the oracle tools, ahead of the game's classes on the class path)
whose `invoke` does the work at once instead of in a thread. Then ending
the human player's turn plays every computer player's turn in order, and
the game after each round is recorded with its generators. The patch can
also keep some players' AI idle (they only end their turns), so the
natives' AI can be checked before the Europeans' exists.

### 4b. Steps

1. **The natives' AI:** `AIMain`, `AIObject`, `AIPlayer`, `AIUnit`,
   `MissionAIPlayer`, `Mission`, `NativeAIPlayer` and its missions
   (wandering, hostile wandering, idling and defending at settlements,
   bringing gifts, demanding goods, seeking and destroying). Checked by
   rounds of new games with only the natives' AI working.
2. **The Europeans' colonies:** `AIColony`, `ColonyPlan`,
   `WorkLocationPlan`, `TileImprovementPlan`, the wishes and `AIGoods`.
3. **The Europeans' units:** the missions (building colonies,
   pioneering, scouting, transport and `Cargo`, wishes, working in
   colonies, treasure, missionaries, privateers, escorts), the military
   coordinator, and `EuropeanAIPlayer`. Checked by rounds with every AI
   working.
4. **The REF's AI**, the AI's objects in saved games, and the engine
   using the AI for its computer players. Then the Phase 3 milestone:
   many rounds of computer players matching Java's.

**Step 1 status: done.** The natives' AI plays as Java's does.
- **`FreeColAI`**, a new module between `FreeColServer` and
  `FreeColEngine`, holds the AI:
  - `AIMain`: an AI object for each computer player, unit (and, later,
    colony). It is told of new objects, of objects removed and of
    owners changing, through a listener `Game` now has, as Java's is.
    It hands each computer player what it is sent, message by message.
  - `AIPlayer`: each player's own generator (seeded from the server's
    when the player was made, the seed kept from step 7), its requests
    as `PlayerCommand`s, and its answers: founding fathers, the
    monarch, first contacts, demands, loot, native trade, names and
    nation summaries. A request is reported as answered even if refused,
    as Java's server API does.
  - `MissionAIPlayer`, `AIUnit` (with `ValuedAIObject` and
    `TransportableAIObject`), and `Mission`, with travelling to a
    target, random moves, and clearing blockages.
  - `NativeAIPlayer`: stances from tension, trading goods between
    settlements, arming braves, defending settlements against threats,
    gifts and demands, missions for the rest, and the natives' side of
    trades.
  - The missions: wandering, hostile wandering, idling at and defending
    settlements, bringing gifts, demanding goods, seeking and destroying.
  - `EuropeanAIPlayer`'s answers (tax raises, with trade suppressed in
    Europe on refusal; mercenaries; founding fathers; native demands).
    Its turns, and its diplomacy, come in steps 2 and 3.
- **Java behaviour kept:**
  - seeking and destroying works out a unit target's score and drops
    it, so only settlements are ever chosen;
  - a demand's tribute goes into the settlement directly, not through
    the server;
  - errors in a unit's mission are caught and the next unit goes on.
- **Checked:** `AIOracle.java` records rounds of Java's AI with the
  patched `AIPlayer`, the Europeans' AI idle: a new game (ten rounds),
  the command game with its colonies (twenty rounds, the AI made
  afresh as Java's server does for a saved game without one), and a
  war game from it (`NativeAIGameMaker.java`, twenty rounds): the
  natives at war with the Dutch (hating them) and the Spanish (angry),
  so they demand goods and attack, happy with the French and the
  English, so they bring gifts, nine Dutch soldiers beside their
  settlements, and gifts and demands likelier. `NativeAITests` plays
  all three and compares, after every round, the game, the server's
  generator and each AI player's own generator (which drifts unseen
  before it shows in the game), and that the AI met nothing unported.
  The recordings are in Tests/JavaOracle/ai.zip (275 KB).
- **Java behaviour kept (found by the war game):** Java's `int`
  arithmetic wraps. A path the search has not settled has 2^30 turns,
  and seek-and-destroy's `1020 - turns * 100` wraps back to 1020, so a
  colony out of reach scores as if one turn away. The AI's scores and
  `RandomChoice`'s totals wrap as Java's do, and casts from `double`
  saturate.
- **Planted bugs:** 5 of 16 caught: wander directions, no arming, no
  stances, first-turn defenders, and the attack tension limit. The 11
  missed change weights and tie-breaks that the three games reach only
  with a single choice, or not at all: the gift and demand weights, the
  home and threat bonuses, the raid and defender values, the fortify
  count, a lone defender, a collected gift, aborting invalid missions,
  and spending moves after wandering. These games show the natives'
  AI matching Java where it is reached, not that every rule is right.
  The European games of steps 2 and 3 will reach more of it.

**Step 2 status: done.** The Europeans' colonies are run as Java's
are.
- **The colonies' AI** in `FreeColAI`:
  - `AIColony`: its exports (which goods to export in full and which
    only to keep the warehouse from filling, and the goods to ship);
    plans to improve the tiles worked, keeping a forest; wishes for
    experts, more people and goods; and rearranging the workers when
    due. Rearranging explores neighbouring rumours, claims free tiles
    (and takes native land if defended), chooses what to build, tries
    the workers on a copy of the colony, has the server apply the
    arrangement, and sets when to rearrange again (before food runs
    out or a warehouse fills). It recovers a colony left with no one
    working, and hears from the colony when it should rearrange
    sooner (Java's `REARRANGE_COLONY` property change).
  - `ColonyPlan`: what to build, by weights for each kind of
    buildable; the two best raw materials; plans for producing goods
    at each work location, the most wanted first; and the trial
    assignment of workers (outdoor experts outside, workers greedily
    to the plans with food when needed, backing out of starvation and
    of running out of raw materials, then experts swapped into their
    work and the rest armed).
  - `WorkLocationPlan`, `TileImprovementPlan`, `Wish`, `GoodsWish`,
    `WorkerWish`, `AIGoods` and `WorkInsideColonyMission`.
  - `EuropeanAIPlayer`: the colony part of its turn: stances (a recent
    peace treaty holding by chance), the conquest nations' hatred of
    natives after turn 100, the badly defended colonies, updating the
    colonies, the maps of tile improvements, wishes and transport, and
    three passes of rearranging the colonies.
  - `AIMain.Works.colonies` works the natives and the Europeans'
    colonies only: the units' other missions, cheating and buying (step
    3) are left out, and the mission getters give none, as in the
    oracle's patch.
- **The model and server:** `Colony.copyColony` and
  `getCorresponding`, a colony's rearrange listener, fired where
  Java's is, the `rearrangeColony` command (Java's
  `RearrangeColonyMessage` and `InGameController.rearrangeColony`),
  `TileImprovementType.improvementValue` for a tile, and
  `WorkLocation.productionOf`.
- **Java behaviour kept:**
  - `WorkLocationPlan`s have no identifier, so Java's `equals` finds
    them all equal and `List.remove(plan)` removes the first plan in
    the list, whichever plan was meant;
  - retrying a plan for more raw material keeps the list the first
    plan came from, so a food plan's list may lose a plan instead;
  - `ColonyPlan.refine` can insert at index -1 and throw, which stops
    the AI's turn (recorded as an error here, so a test would show it);
  - the goods types to export are shared by all AI colonies in Java,
    but each colony sets them before using them, so each keeps its own.
- **Checked:** the oracle runs with a patched `EuropeanAIPlayer` as
  well (`-Dfreecol.oracle.aiWorks=colonies`), which works only the
  colonies, and `AIOracle.java` records, after every round, what the AI
  keeps for each colony: the next rearrangement, the plan's buildables,
  and the wishes, tile improvement plans and exports with their
  identifiers and values. `NativeAITests` plays twenty rounds each of
  the command game, the war game, and a game made for the colonies'
  AI (`ColonyAIGameMaker.java`: a rumour beside a colony with
  colonists to explore it, tiles to claim, colonies nearly out of food
  or lumber, and a colony with no one working). Every round's game,
  generators and AI colonies match Java's. The recordings are in
  Tests/JavaOracle/ai.zip (602 KB).
- **Not reached by these games:** retrying and giving up for raw
  materials, subsisting and the harmless placement of a last worker,
  swapping a waiting expert in, a failed trial, and taking native land
  (which needs a defender with a mission, step 3).
- **Planted bugs:** 14 of 20 caught: the goods wish value, the worker
  wish decay, the export minimum and level, the forest minimum, the
  rearrangement horizon and warehouse limit, no claims, unsorted
  wishes, the fish and liberty weights, the least-skilled tie-break,
  the soldiers' order, and no rearming. The 6 missed: the turnover
  turns (starvation is reached, but not at the edge), removing the
  plan meant rather than the first (the lists' first plans fail in
  these games), the national bonus, the tie between equal tile
  improvements, the server not retrying a full work location, and one
  rearrangement pass instead of three (the later passes find nothing
  due). As for the natives, these games show the colonies' AI
  matching Java where reached.

**Step 3 status: done.** The Europeans' AI plays as Java's does, with
every computer player working.
- **Transport:** `Cargo` (where carrier and transportable meet, where
  it is dropped, and the turns it takes), and `TransportMission`
  (checking its cargoes, loading and unloading where it is, the order
  of its targets by Java's permutations, taking on the best cargo and
  what is easily carried, attacking or dodging blockages). AI units and
  goods join and leave carriers, and plan deliveries.
- **The missions:** building colonies (claiming, buying or stealing the
  land), pioneering, realizing wishes, cashing in treasure, scouting,
  missionaries, privateering and escorting, with working inside
  colonies from step 2.
- **The military coordinator** (`MilitaryCoordinator`, `DefensiveMap`,
  `DefensiveZone`): defenders for the colonies, by the zones of land
  around them, counterattacks, artillery attacks with escorts, and the
  rest defending or wandering.
- **`EuropeanAIPlayer`:** the first turn's missions for the units
  aboard ships; Java's cheats (lifting boycotts, equipping scouts and
  pioneers, units for wishes, ships); buying ships, artillery,
  dragoons and wished-for workers in Europe; giving units missions to
  quotas of builders, scouts and pioneers, then simple missions, then
  the ships, then fallbacks; three passes of rearranging colonies,
  giving missions and carrying them out; and diplomacy (judging trades
  by strength, dropping the worst items, Franklin's peace).
- **Fixed in the model:** `PathNode.direction` read the previous node,
  which is weak, so a node kept without its path's head lost its
  direction; it now keeps the previous tile, which the map holds. The
  path search's cache was one global shared by every thread, so tests
  running at once could corrupt each other's (the intermittent crash
  of steps 1 and 2); it is now task local. Native settlements on the
  server work out their most hated player whenever an alarm is set, as
  Java's `ServerIndianSettlement` does, and alarms changed in place are
  stored without it.
- **Java behaviour kept:**
  - Java's naval strength ratio looks for the player among the other
    players, so its own strength is always zero (and the naval cheat
    only happens with no navy at all);
  - the military coordinator's counterattacks check the turns of a
    path's first node, which are always zero;
  - realizing a wish gives the unit a new mission and then drops it;
  - a transport mission that turns privateer drops the new mission;
  - `PioneeringMission`'s failure drops the mission even when told to
    continue;
  - missions keep a target colony that has been destroyed;
  - Java's urgent transportables are always none, so supply-driven
    transport allocation does nothing.
- **Made repeatable in the oracle:** Java's military coordinator keeps
  units in identity hash sets, whose order follows identity hash codes
  and so differs from run to run; the oracle's patched
  `MilitaryCoordinator` keeps them in the order they came, which the
  Swift port follows, and the hash sets they come from are in Java's
  `HashSet` order (from `AIUnit.hashCode`, here `javaHash`).
  `buyShip` shuffles with Java's unseeded generator; the patch keeps
  the specification's order. Diplomacy scores trade items in a
  `HashMap`, whose order for stances also follows an enum's identity
  hash; the items' order is used, which matters only for offers of
  several items.
- **Checked:** with every AI working, `AIOracle.java` also records
  each European AI unit's mission, target and carrier after every
  round. `NativeAITests` plays a new game (ten rounds) and the command,
  war, colony and units games (twenty rounds each), all matching Java's
  every round: the game, the generators, the AI colonies and every AI
  unit's mission. Tests/JavaOracle/ai.zip holds all eleven AI
  recordings (1.2 MB).
- **The units game:** `UnitAIGameMaker.java` makes it from the war
  game, for what the other games never reach:
  - the European AIs have gold to buy units with (they had none);
  - six French units wait on the docks, one short of buying a ship;
  - each AI has a seasoned scout;
  - the Spanish have three artillery on open land, so one is left
    after two go to their larger colonies, with dragoons exactly seven
    turns away, as measured by Java;
  - free English colonists stand on open land;
  - English privateers have laden Dutch ships beside them, one of
    them a galleon worth a little more than the colony next to it.
  Its first runs found two port bugs:
  - privateers read a ship's raw visible goods count, which is -1
    until set, instead of Java's value, which falls back to the goods
    carried, so they never went after cargo;
  - the seek-and-destroy mission held its target weakly, losing a
    destroyed target that Java keeps.
- **Not ported:** the mercenary cheat after turn 300, and evaluating
  colony, goods, unit and incitement trade items (recorded as not yet
  ported if met).
- **Planted bugs:** 8 of 22 caught. The four older every-AI games
  catch 2: the transport's destination bound and its cargo refill
  threshold. The units game adds 6: the escort's reach, the defensive
  zone size, buying a ship for a full dock, the dragoons needed, the
  privateer's greed, and the military units' order. Missed:
  - four can hardly ever show:
    - lowering the builder score by 100 cannot change the order it
      sorts units in (non-experts stay above experts);
    - the pioneer and rumour scores only scale every candidate;
    - the peace odds change only when the random number lands exactly
      on the threshold, 1 time in 100;
  - the others need situations none of these games reach: favouring
    early deliveries, the cargo retries, builders needed with no
    ports, the colony site's extra turns, the builder's transport
    priority, the defence weighting, the defender adjustment (used only
    when a defended colony is lost), the building range, the
    seek-and-destroy range, and the safest landing tile.
  Scores matter less than they seem: the map search stops expanding
  past the cost of the best goal it has found, so a unit weighs only
  targets about as near as the first. That is why scaling a score
  rarely changes the outcome, and why the privateer test needed a
  target right next to the colony.


**Step 4 status: done.** The REF fights as Java's does, the AI is
saved and loaded with the game, the engine's computer players are the
AI, and long games with computer players match Java's every round, the
Phase 3 milestone.
- **The REF's AI** (`REFAIPlayer.swift`): before its first turn it
  chooses where to land (the rebels' ports reachable by sea, scored
  with a little chance and sorted lowest first, as Java's natural
  order of the scores has it), sends its army there, two thirds at the
  first target, and its empty ships after the rebels' ships near the
  landings, or patrolling. Each turn it keeps enough carriers, sends
  its free army to attack nearby, defend or wait at a port, and loads
  those waiting onto carriers there for new attacks, before the
  European AI's missions for the rest. It garrisons thinly, values
  ports highly, leaves the rebels' units alone until it holds a
  colony, and has its own stances.
- **The server's part:** the REF's AI player is made when the REF is
  (its seed drawn then, as Java's makeAIPlayer does), the REF is
  launched once its AI has chosen (csLaunchREF: sailing in from the
  high seas, or appearing where it lands with teleportREF), and the
  intervention force arrives off a rebel port when the rebels have
  rung enough bells. A hook on InGameController (`initializeREF`) lets
  the server, below the AI, ask it.
- **The AI in saved games** (`AISaving.swift` and each AI class):
  every AI object is written in identifier order under `aiMain`, and
  read back with references made empty until their own elements come,
  as Java's makeAIObject does. Java's integrity checks are ported:
  objects failing them are dropped when saving and when loading, and
  those missing are made afresh. The save reader keeps the `aiMain`
  element for the AI to read once it is made. Java's quirks are kept:
  - a loaded unit's transport priority is its mission's, not as saved
    (the mission takes the unit, and with it the priority, before its
    element is read);
  - a loaded AI colony does not listen for its colony asking to be
    rearranged;
  - wishes not yet being carried are not saved, nor one-time or
    invalid missions, nor cargoes to be dumped;
  - plans are saved only if still sound, and pioneers only if wholly
    so.
  `ServerGame.finishLoading` does what Java's server does with a game
  it has read: the map's regions again, the unknown enemy, and the
  players sorted by rank (the natives, the computer Europeans, the
  human administrator last), which is the turn order from then on.
- **The engine:** `GameEngine` makes the AI for a new game, reads it
  from a saved game (or makes it afresh), passes the computer players
  what they are sent so they play their turns, and saves the AI with
  the game. A loaded game does not play on as the live one did, as the
  AI keeps more than it saves (Java's too), but every load of it plays
  the same.
- **Fixed on the way:** a remembered copy of a native settlement (a
  player's cached tile) is read as Java reads it, as a plain
  settlement, so setting its alarm does not work out its most hated
  player again, which lost it.
- **The oracle:** `AIOracle.java` gains `--reload-at k file.fsg` (save
  the game, AI and all, after round k, and load it back as Java's
  server does to play on) and `--declare` (the human declares
  independence at the start of the first round, through the message
  handler). `REFGameMaker.java` makes a game where the Dutch may
  declare, with a continental army to muster and the intervention
  force due after 100 bells. A fourth oracle patch keeps Java's river
  names in the rules' order: Java shuffles them with an unseeded
  generator, so a REF naming a region would not repeat.
- **Checked:**
  - the AI saved as Java's after five rounds of the new game and ten
    of the units game (cargoes, export goods, plans, wishes and most
    missions), the written `aiMain` the same as Java's;
  - Java's saves of those read back and played on, five and ten
    rounds, as Java's after loading;
  - the REF game for twenty rounds: the declaration, the REF's AI
    player and its landing, the fighting, colonies taken, and the
    intervention force;
  - sixty rounds of two new games (seeds 11 and 2), every computer
    player as Java's every round (95 seconds in a release build);
  - the engine's computer players as Java's for ten rounds of the new
    game, and its saved games loading and playing on alike.
  Tests/JavaOracle/ai.zip holds all sixteen AI recordings.
- **Limits:** Java's oracle can not play the REF game past twenty
  rounds: with every AI answering on one thread, the nested messages
  overflow the stack in round 21. The game's own integrity check on
  loading (Game.checkIntegrity) is still not ported; Java's saves pass
  it unchanged.
- **Planted bugs:** 11 of 24 caught.
  - Saving and loading, 7 of 9: a value not saved, a loaded unit
    keeping its saved priority, loaded colonies listening, the players
    not sorted after loading, a cargo's tries not saved, a remembered
    settlement read as the server's, and the engine not saving the AI.
    Missed, as these games can not show them: saving pioneers that are
    only fixable (none are), and a wish read from its own element
    joining its colony (colonies come first by identifier and list
    their wishes, so Java's saves never take that path).
  - The REF, 4 of 15: its bonus for ports, its stance towards those at
    war with it, its AI's seed drawn when the REF is made, and how it
    lets defenders go. Missed: the order of its targets, their random
    twiddle, two thirds of the army to the first and the bonus for
    landing unseen (on its first turn the REF has no estimate of the
    rebels' strength, so it goes for one target, and the stealth pass
    sorts the targets again anyway), the time to sail in (moving a REF
    ship onto the high seas sets it to nought, so it can never show),
    how many may chase one unit, how far it seeks, its lesser interest
    in units, its minimum of carriers, the intervention force's search
    for open sea, and a reset in allocating transport. Most need a REF
    with several targets, or a rebel who moves; the human of these
    games only ends its turns.
## Phase 5: iOS user interface (replaces ~72k lines of Swing)

Prototyping can start after Phase 1. A read-only map viewer for a loaded
save is a good early demo.

- **Map: SwiftUI `Canvas` first.** Draw tiles in layers (terrain,
  transitions between terrain types, rivers, roads, resources, units,
  settlements, fog of war). Pinch to zoom, pan, tap to select, long-press
  for menus.
  - Start with the read-only map viewer in `Canvas`, with no other
    framework. It keeps the whole app in SwiftUI and is the simplest
    thing to try.
  - Do the obvious work by hand from the start: draw only the tiles on
    screen, load each image once with `context.resolve`, and keep the
    map drawing out of the views that change often (the selected unit,
    the info panel), so they don't make the map redraw.
  - Keep the drawing code separate from the screen code: the code that
    decides which tile layers to draw, in what order and where shouldn't
    import SwiftUI. Then moving to SpriteKit later only means
    rewriting the part that puts images on screen.
  - **When to switch:** measure on the oldest iPad to be supported, with
    the largest map size, while panning and zooming, and later with units
    moving and fog of war. If it can't hold 60 frames per second, move
    the map to SpriteKit inside a `SpriteView`. Metal is the fallback
    only if SpriteKit is also too slow. The other screens stay SwiftUI
    either way.
- **Screens in SwiftUI:** colony screen (drag colonists between buildings
  and fields), Europe/docks, the Continental Congress screen, reports, the
  diplomacy and trade screens, game setup, save/load.
- **Redesign for touch:** right-clicks become long-presses and context
  menus, the many small pop-up dialogs become sheets, and the unit action
  bar is sized for thumbs.
- **Hooks into the system:** the save folder (Files app and iCloud), a
  background save when the app is suspended, haptics, VoiceOver labels
  taken from the existing translated strings.

## Phase 6: Polish and release

- Sound and music (`common/sound` → AVFoundation), all translations, high
  scores, the tutorial.
- Performance on large maps (profile pathfinding and AI turns on older
  iPads).
- Optional: mods, Game Center, the Mac (Mac Catalyst or native).
- Release: depends on the license decision from Phase 0.

## Size and order

| Phase              | Java ported                       | Can run in parallel with |
|--------------------|-----------------------------------|--------------------------|
| 0 Comparison tools | –                                 | –                        |
| 1 Model            | ~67k + util/io/option/i18n ~17k   | –                        |
| 2 Data files       | ~7k                               | Phase 1, after step 4    |
| 3 Turn processing  | ~20k                              | UI prototype             |
| 4 AI               | ~25k                              | UI work                  |
| 5 UI               | replaces ~72k                     | Phases 3–4               |
| 6 Polish           | –                                 | –                        |

## Biggest risks

1. **Tiny numeric differences** (rounding, floating point, random
   sequences) breaking the comparison tests. Phase 0's dumps and the exact
   random port keep this under control.
2. **Object lifetime and reference cycles** in the model graph, because
   Swift counts references where Java has a garbage collector. Decide who
   owns what in Phase 1 step 1 and keep to it. (Decided: as in Java, a
   weak registry, strong containment and weak back-references. See 1c.)
3. **Making the UI work well on touch.** This is design work, not
   translation, so prototype it early.
