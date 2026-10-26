# FreeCol for iOS

A port of [FreeCol](http://www.freecol.org/), the turn-based strategy game
based on Colonization, from Java to Swift, for iOS.

The original Java version came from
<https://sourceforge.net/p/freecol/git/ci/master/tree/>.
This repository holds only what the Swift version needs: the Swift code and
the game's data files. None of the Java code is here.

## What is here

- `swift/FreeColKit/`: the game engine as a Swift package (iOS 17+, macOS 14+,
  Swift 6), with no UIKit or SwiftUI, so it builds and tests on macOS:
  - `FreeColUtil`, `FreeColXML`: Java-compatible helpers (random numbers,
    rounding, strings, hash map order) and XML reading and writing;
  - `FreeColCore`: the game model and rules;
  - `FreeColIO`, `FreeColResources`: saved games, data files and resources;
  - `FreeColServer`: turn processing and the players' commands, without a
    network.
- `data/`: FreeCol's rules, translations, maps, mods, images and sounds,
  unchanged from the original.
- `test/expected-data/`: tile production figures checked against the
  original game, used by the tests.
- `doc/swift-port-plan.md`: the plan for the port, with what each step
  ported and how it was checked.
- `LICENSE`: the GNU General Public License, version 2, as for FreeCol.

## Building and testing

```
cd swift/FreeColKit
swift build
swift test
```

For the iOS Simulator:

```
cd swift/FreeColKit
xcodebuild -scheme FreeColKit -destination 'generic/platform=iOS Simulator' build
```

## How the port is checked

Each step was checked against the Java game itself. Tools in the Java
repository recorded what the Java code does (`src/net/sf/freecol/tools/dump`
there), and their recordings are kept with the tests in
`swift/FreeColKit/Tests/JavaOracle`, so the tests run without Java. The tests
that compare with larger reference dumps (`build/dumps`, made by
`swift/scripts/make-reference-dumps.sh` in the Java repository) are skipped
when the dumps are not present.

## Status

The game model, data loading, XML, the new turn, the turn cycle, and the
players' commands for units, colonies, goods, Europe, moving, dealing with
natives, combat, diplomacy, the monarch and independence are ported. Map
generation, the AI (which the REF needs to arrive) and the user interface
are still to come. See `doc/swift-port-plan.md`.

## Licence

FreeCol is free software, released under the GNU General Public License,
version 2 or (at your option) any later version. See `LICENSE`.
