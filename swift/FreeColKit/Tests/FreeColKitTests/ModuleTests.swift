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

import Testing
import FreeColUtil
import FreeColXML
import FreeColCore
import FreeColI18n
import FreeColIO
import FreeColResources
import FreeColServer

/// Checks that every engine module builds and links.  FreeColCore no
/// longer has a placeholder; its own tests cover it.
struct ModuleTests {

    @Test func everyModuleNamesItsJavaSource() {
        let modules = [
            FreeColUtil.javaPackages, FreeColXML.javaPackages,
            FreeColI18n.javaPackages, FreeColIO.javaPackages,
            FreeColResources.javaPackages, FreeColServer.javaPackages,
        ]
        for packages in modules {
            #expect(!packages.isEmpty)
            #expect(packages.allSatisfy { $0.hasPrefix("net.sf.freecol.") })
        }
    }
}
