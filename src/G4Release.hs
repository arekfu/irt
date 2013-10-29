{-# LANGUAGE RankNTypes, KindSignatures, DeriveDataTypeable #-}
module G4Release (
  G4Module(..),
  G4ReleaseOption(..),
  mkModuleDefinition,
  releaseG4,
  releaseG4Abla
  ) where

import System.FilePath
import System.Directory
import FindFile
import GitRunner
import SedRunner
import Data.Typeable
import Data.Data

data G4Module = G4Module {
  g4moduleCode :: String,
  g4moduleName :: String,
  g4moduleDir :: FilePath,
  g4moduleHeaders :: [FilePath],
  g4moduleSources :: [FilePath],
  g4moduleGranularDependencies :: [String],
  g4moduleGlobalDependencies :: [String]
  } deriving (Show, Eq)

data G4ReleaseOption = AllowAssert
                     | NoG4Types
                     | NoLicense
                     | RevisionInfo
                     deriving (Show, Eq, Data, Typeable)

identityTransform :: String -> IO String
identityTransform code = do
  return code

transformFn :: [G4ReleaseOption] -> GitRepo -> String -> IO String
transformFn g4options repo code =
  let initialTransform = identityTransform code >>= appendDefines
      typeTransform = case elem NoG4Types g4options of
        True -> identityTransform
        False -> useG4Types
      licenseInfoTransform = case elem NoLicense g4options of
        True -> identityTransform
        False -> (appendLicense licenseBoilerplate)
      revisionInfoTransform = case elem RevisionInfo g4options of
        True -> (appendRevisionInfo repo "INCL++")
        False -> identityTransform
      assertEliminationTransform = case elem AllowAssert g4options of
        True -> identityTransform
        False -> disableAssertions
  in initialTransform >>= typeTransform >>= assertEliminationTransform >>= revisionInfoTransform >>= licenseInfoTransform

transformAblaFn :: [G4ReleaseOption] -> GitRepo -> String -> IO String
transformAblaFn g4options repo code =
  let initialTransform = identityTransform code >>= appendDefinesABLAXX
      licenseInfoTransform = case elem NoLicense g4options of
        True -> identityTransform
        False -> (appendLicense licenseBoilerplateABLAXX)
      revisionInfoTransform = case elem RevisionInfo g4options of
        True -> (appendRevisionInfo repo "ABLAXX")
        False -> identityTransform
      assertEliminationTransform = case elem AllowAssert g4options of
        True -> identityTransform
        False -> disableAssertions
  in initialTransform >>= typeTransform >>= assertEliminationTransform >>= revisionInfoTransform >>= licenseInfoTransform

releaseG4 :: GitRepo -> FilePath -> [G4Module] -> [G4ReleaseOption] -> IO ()
releaseG4 repo targetdir modules g4options = do
  let transform = transformFn g4options repo
      releaseFn = releaseModule targetdir transform
  mapM_ releaseFn modules

releaseG4Abla :: GitRepo -> FilePath -> G4Module -> [G4ReleaseOption] -> IO ()
releaseG4Abla repo targetdir g4mod g4options = do
  let transform = transformAblaFn g4options repo
  releaseAbla targetdir transform g4mod

-- Apply transform (String -> IO String) to a code file:
releaseFile :: FilePath -> (String -> IO String) -> FilePath -> IO ()
releaseFile destinationDir transform file = do
  putStrLn ("Processing " ++ file)
  code <- readFile file
  code' <- transform code
  let fileName = takeFileName file
      targetFileName = destinationDir </> fileName
  writeFile targetFileName code'

releaseModule :: FilePath -> (String -> IO String) -> G4Module -> IO ()
releaseModule targetRootDir transform g4module = do
  createDirectoryIfMissing True targetRootDir
  let modDir = g4moduleDir g4module
      headers = g4moduleHeaders g4module      
      sources = g4moduleSources g4module      
  createDirectoryIfMissing True (targetRootDir </> modDir </> "include")
  createDirectoryIfMissing True (targetRootDir </> modDir </> "src")
  mapM_ (releaseFile (targetRootDir </> modDir </> "include") transform) headers
  mapM_ (releaseFile (targetRootDir </> modDir </> "src") transform) sources
  createCMakeSources targetRootDir "inclxx" g4module

releaseAbla :: FilePath -> (String -> IO String) -> G4Module -> IO ()
releaseAbla targetRootDir transform g4module = do
  createDirectoryIfMissing True targetRootDir
  let modDir = g4moduleDir g4module
      headers = g4moduleHeaders g4module
      sources = g4moduleSources g4module
  createDirectoryIfMissing True (targetRootDir </> modDir </> "include")
  createDirectoryIfMissing True (targetRootDir </> modDir </> "src")
  mapM_ (releaseFile (targetRootDir </> modDir </> "include") transform) headers
  mapM_ (releaseFile (targetRootDir </> modDir </> "src") transform) sources
  createCMakeSources targetRootDir "abla" g4module

createCMakeSources :: FilePath -> String -> G4Module -> IO ()
createCMakeSources targetRootDir suffix g4mod = do
  let sources = generateCMakeSources suffix g4mod
      fname = targetRootDir </> (g4moduleDir g4mod) </> "sources.cmake"
  writeFile fname sources

-- Boilerplate to be added to each file

appendDefines :: String -> IO String
appendDefines code = do
  let codeText = lines code
      defines = ["#define INCLXX_IN_GEANT4_MODE 1\n", "#include \"globals.hh\"\n"]
      codeText' = concat [defines, codeText]
      code' = unlines codeText'
  return code'

appendDefinesABLAXX :: String -> IO String
appendDefinesABLAXX code = do
  let codeText = lines code
      defines = ["#define ABLAXX_IN_GEANT4_MODE 1\n", "#include \"globals.hh\"\n"]
      codeText' = concat [defines, codeText]
      code' = unlines codeText'
  return code'

appendLicense :: String -> String -> IO String
appendLicense license code = do
  let licenseText = lines license
      codeText = lines code
      combinedTexts = concat [licenseText, codeText]
      code' = unlines combinedTexts
  return code'

appendRevisionInfo :: GitRepo -> String -> String -> IO String
appendRevisionInfo repo name code = do
  revStr <- buildGitRevisionString repo
  let revText = lines $ "// " ++ name ++ " revision: " ++ revStr ++ "\n//\n"
      codeText = lines code
      combinedTexts = concat [revText, codeText]
      code' = unlines combinedTexts
  return code'

licenseBoilerplate :: String
licenseBoilerplate = "//\n\
\// ********************************************************************\n\
\// * License and Disclaimer                                           *\n\
\// *                                                                  *\n\
\// * The  Geant4 software  is  copyright of the Copyright Holders  of *\n\
\// * the Geant4 Collaboration.  It is provided  under  the terms  and *\n\
\// * conditions of the Geant4 Software License,  included in the file *\n\
\// * LICENSE and available at  http://cern.ch/geant4/license .  These *\n\
\// * include a list of copyright holders.                             *\n\
\// *                                                                  *\n\
\// * Neither the authors of this software system, nor their employing *\n\
\// * institutes,nor the agencies providing financial support for this *\n\
\// * work  make  any representation or  warranty, express or implied, *\n\
\// * regarding  this  software system or assume any liability for its *\n\
\// * use.  Please see the license in the file  LICENSE  and URL above *\n\
\// * for the full disclaimer and the limitation of liability.         *\n\
\// *                                                                  *\n\
\// * This  code  implementation is the result of  the  scientific and *\n\
\// * technical work of the GEANT4 collaboration.                      *\n\
\// * By using,  copying,  modifying or  distributing the software (or *\n\
\// * any work based  on the software)  you  agree  to acknowledge its *\n\
\// * use  in  resulting  scientific  publications,  and indicate your *\n\
\// * acceptance of all terms of the Geant4 Software license.          *\n\
\// ********************************************************************\n\
\//\n\
\// INCL++ intra-nuclear cascade model\n\
\// Pekka Kaitaniemi, CEA and Helsinki Institute of Physics\n\
\// Davide Mancusi, CEA\n\
\// Alain Boudard, CEA\n\
\// Sylvie Leray, CEA\n\
\// Joseph Cugnon, University of Liege\n\
\//\n"

licenseBoilerplateABLAXX :: String
licenseBoilerplateABLAXX = "//\n\
\// ********************************************************************\n\
\// * License and Disclaimer                                           *\n\
\// *                                                                  *\n\
\// * The  Geant4 software  is  copyright of the Copyright Holders  of *\n\
\// * the Geant4 Collaboration.  It is provided  under  the terms  and *\n\
\// * conditions of the Geant4 Software License,  included in the file *\n\
\// * LICENSE and available at  http://cern.ch/geant4/license .  These *\n\
\// * include a list of copyright holders.                             *\n\
\// *                                                                  *\n\
\// * Neither the authors of this software system, nor their employing *\n\
\// * institutes,nor the agencies providing financial support for this *\n\
\// * work  make  any representation or  warranty, express or implied, *\n\
\// * regarding  this  software system or assume any liability for its *\n\
\// * use.  Please see the license in the file  LICENSE  and URL above *\n\
\// * for the full disclaimer and the limitation of liability.         *\n\
\// *                                                                  *\n\
\// * This  code  implementation is the result of  the  scientific and *\n\
\// * technical work of the GEANT4 collaboration.                      *\n\
\// * By using,  copying,  modifying or  distributing the software (or *\n\
\// * any work based  on the software)  you  agree  to acknowledge its *\n\
\// * use  in  resulting  scientific  publications,  and indicate your *\n\
\// * acceptance of all terms of the Geant4 Software license.          *\n\
\// ********************************************************************\n\
\//\n\
\// ABLAXX statistical de-excitation model\n\
\// Pekka Kaitaniemi, HIP (translation)\n\
\// Christelle Schmidt, IPNL (fission code)\n\
\// Davide Mancusi, CEA (contact person INCL/ABLA)\n\
\// Aatos Heikkinen, HIP (project coordination)\n\
\//\n"

-- G4 build system code generator

defaultGlobDeps :: [String]
defaultGlobDeps = ["G4geometry", "G4global", "G4materials",
                   "G4particles", "G4track", "G4intercoms"]

defaultGranDeps :: [String]
defaultGranDeps = ["G4baryons", "G4bosons", "G4geometrymng",
                   "G4globman",
                   "G4ions", "G4leptons",
                   "G4materials", "G4mesons", "G4partman",
                   "G4procman", "G4track", "G4volumes",
                   "G4intercoms",
                   "G4had_preequ_exciton",
                   "G4hadronic_mgt", "G4hadronic_util", "G4hadronic_xsect",
                   "G4had_mod_man", "G4had_mod_util",
                   "G4hadronic_deex_evaporation",
                   "G4hadronic_deex_fermi_breakup", "G4hadronic_deex_handler", "G4hadronic_deex_management",
                   "G4hadronic_deex_multifragmentation", "G4hadronic_deex_photon_evaporation", "G4hadronic_deex_util"
                   ]

specificGranDeps :: String -> [String]
specificGranDeps "physics" = [ "G4baryons", "G4bosons", "G4geometrymng",
                 "G4globman",
                 "G4hadronic_mgt", "G4hadronic_util", "G4hadronic_xsect",
                 "G4ions", "G4leptons",
                 "G4materials", "G4mesons", "G4partman",
                 "G4procman", "G4track", "G4volumes",
                 "G4intercoms",
                 "G4had_preequ_exciton",
                 "G4hadronic_deex_evaporation",
                 "G4hadronic_deex_fermi_breakup", "G4hadronic_deex_handler", "G4hadronic_deex_management",
                 "G4hadronic_deex_multifragmentation", "G4hadronic_deex_photon_evaporation", "G4hadronic_deex_util"
                 ]
specificGranDeps "utils" = [ "G4baryons", "G4bosons", "G4geometrymng",
                 "G4globman",
                 "G4ions", "G4leptons",
                 "G4materials", "G4mesons", "G4partman",
                 "G4procman", "G4track", "G4volumes",
                 "G4intercoms",
                 "G4had_mod_man",
                 "G4had_preequ_exciton",
                 "G4hadronic_mgt", "G4hadronic_util", "G4hadronic_xsect",
                 "G4hadronic_deex_evaporation",
                 "G4hadronic_deex_fermi_breakup", "G4hadronic_deex_handler", "G4hadronic_deex_management",
                 "G4hadronic_deex_multifragmentation", "G4hadronic_deex_photon_evaporation", "G4hadronic_deex_util"
                 ]
specificGranDeps "interface" = [ "G4baryons", "G4bosons", "G4geometrymng",
                 "G4globman",
                 "G4hadronic_mgt", "G4hadronic_util", "G4hadronic_xsect",
                 "G4ions", "G4leptons",
                 "G4materials", "G4mesons", "G4partman",
                 "G4procman", "G4track", "G4volumes",
                 "G4intercoms",
                 "G4had_preequ_exciton",
                 "G4had_mod_man", "G4had_mod_util",
                 "G4hadronic_deex_evaporation",
                 "G4hadronic_deex_fermi_breakup", "G4hadronic_deex_handler", "G4hadronic_deex_management",
                 "G4hadronic_deex_multifragmentation", "G4hadronic_deex_photon_evaporation", "G4hadronic_deex_util"
                 ]
specificGranDeps "abla" = [ "G4baryons", "G4bosons", "G4geometrymng",
                 "G4globman",
                 "G4hadronic_mgt", "G4hadronic_util", "G4hadronic_xsect",
                 "G4ions", "G4leptons",
                 "G4materials", "G4mesons", "G4partman",
                 "G4procman", "G4track", "G4volumes",
                 "G4intercoms"
                 ]
specificGranDeps _ = defaultGranDeps

mkModuleDefinition :: FilePath -> FilePath -> String -> String -> [G4Module] -> IO G4Module
mkModuleDefinition basedir pkgdir codename pkgname granularDeps = do
  let  name = pkgname
       cname = codename
  moduleFiles <- getRecursiveContents (basedir </> pkgdir)
  let headers = headerFilesOnly moduleFiles
      sources = sourceFilesOnly moduleFiles
      prefix = "G4hadronic_" ++ codename ++ "_"
      intGranDeps = map g4moduleName granularDeps
      g4modulesGranDeps = map ((++) prefix) intGranDeps
      moduleGranDeps = specificGranDeps name
      granDeps = concat [moduleGranDeps, g4modulesGranDeps]
      globDeps = defaultGlobDeps
      newModule = G4Module cname name pkgdir headers sources granDeps globDeps
  return newModule

generateCMakeSources :: String -> G4Module -> String
generateCMakeSources suffix g4mod = concat [sourcesCMakeHeader,
                                     includeDirs,
                                     sourcesCMakeInterlude,
                                     "GEANT4_DEFINE_MODULE(NAME " ++ moduleName ++ "\n",
                                     headerDefs,
                                     "\n",
                                     sourceDefs,
                                     "\n",
                                     granularDepDefs,
                                     "\n",
                                     globalDepDefs,
                                     "\n",
                                     sourcesCMakeEnd]
  where moduleName = "G4hadronic_" ++ suffix ++ "_" ++ (g4moduleName g4mod)
        includeDirs = specificIncludeDirsCMake g4mod
        appendEndl fname = "        " ++ fname ++ "\n"
        headerFiles = map takeFileName (g4moduleHeaders g4mod)
        headerFilesWithEndl = concat $ map appendEndl headerFiles
        headerDefs = "    HEADERS\n" ++ headerFilesWithEndl
        sourceFiles = map takeFileName (g4moduleSources g4mod)
        sourceFilesWithEndl = concat $ map appendEndl sourceFiles
        sourceDefs = "    SOURCES\n" ++ sourceFilesWithEndl
        granularDepDefs = "    GRANULAR_DEPENDENCIES\n" ++ (concat (map appendEndl (g4moduleGranularDependencies g4mod)))
        globalDepDefs = "    GLOBAL_DEPENDENCIES\n" ++ (concat (map appendEndl (g4moduleGlobalDependencies g4mod)))

sourcesCMakeEnd :: String
sourcesCMakeEnd = "LINK_LIBRARIES\
\)\
\# List any source specific properties here"

sourcesCMakeHeader :: String
sourcesCMakeHeader = "#------------------------------------------------------------------------------\n\
\# sources.cmake\n\
\# Module : G4hadronic_hetcpp_utils\n\
\# Package: Geant4.src.G4processes.G4hadronic.G4hadronic_models.G4had_hetcpp.G4hadronic_hetcpp_utils\n\
\#\n\
\# Sources description for a library.\n\
\# Lists the sources and headers of the code explicitely.\n\
\# Lists include paths needed.\n\
\# Lists the internal granular and global dependencies of the library.\n\
\# Source specific properties should be added at the end.\n\
\#\n\
\# Generated on : 24/9/2010\n\
\#\n\
\# $Id$\n\
\#\n\
\#------------------------------------------------------------------------------\n\
\\n\
\# List external includes needed.\n\
\include_directories(${CLHEP_INCLUDE_DIRS})\n\
\\n\
\# List internal includes needed.\n"

sourcesCMakeInterlude :: String
sourcesCMakeInterlude = "\n\
\#\n\
\# Define the Geant4 Module.\n\
\#\n\
\include(Geant4MacroDefineModule)\n"

includeDirToCMakeInclude :: String -> String
includeDirToCMakeInclude dir = "include_directories(${CMAKE_SOURCE_DIR}/source/" ++ dir ++ ")\n"

specificIncludeDirsCMake :: G4Module -> String
specificIncludeDirsCMake g4mod = cmakeDirs
  where cmakeDirs = concat cmakeList
        cmakeList = map includeDirToCMakeInclude dirs
        dirs = specificIncludeDirs moduleName
        moduleName = g4moduleName g4mod

specificIncludeDirs :: String -> [String]
specificIncludeDirs "utils" = [ "geometry/management/include",
                    "geometry/volumes/include",
                    "global/HEPGeometry/include",
                    "global/HEPRandom/include",
                    "global/management/include",
                    "materials/include",
                    "particles/bosons/include",
                    "particles/hadrons/barions/include",
                    "particles/hadrons/ions/include",
                    "particles/hadrons/mesons/include",
                    "particles/leptons/include",
                    "particles/management/include",
                    "processes/hadronic/cross_sections/include",
                    "processes/hadronic/management/include",
                    "processes/hadronic/models/binary_cascade/include",
                    "processes/hadronic/models/im_r_matrix/include",
                    "processes/hadronic/models/pre_equilibrium/exciton_model/include",
                    "processes/hadronic/models/management/include",
                    "processes/hadronic/util/include",
                    "processes/management/include",
                    "track/include",
                    "intercoms/include"
                    ]
specificIncludeDirs "physics" = [ "geometry/management/include",
                    "geometry/volumes/include",
                    "global/HEPGeometry/include",
                    "global/HEPRandom/include",
                    "global/management/include",
                    "materials/include",
                    "particles/bosons/include",
                    "particles/hadrons/barions/include",
                    "particles/hadrons/ions/include",
                    "particles/hadrons/mesons/include",
                    "particles/leptons/include",
                    "particles/management/include",
                    "processes/hadronic/cross_sections/include",
                    "processes/hadronic/management/include",
                    "processes/hadronic/models/binary_cascade/include",
                    "processes/hadronic/models/im_r_matrix/include",
                    "processes/hadronic/models/management/include",
                    "processes/hadronic/util/include",
                    "processes/management/include",
                    "track/include",
                    "intercoms/include"
                    ]
specificIncludeDirs "interface" = [ "geometry/management/include",
                    "geometry/volumes/include",
                    "global/HEPGeometry/include",
                    "global/HEPRandom/include",
                    "global/management/include",
                    "materials/include",
                    "particles/bosons/include",
                    "particles/hadrons/barions/include",
                    "particles/hadrons/ions/include",
                    "particles/hadrons/mesons/include",
                    "particles/leptons/include",
                    "particles/management/include",
                    "processes/hadronic/cross_sections/include",
                    "processes/hadronic/management/include",
                    "processes/hadronic/models/binary_cascade/include",
                    "processes/hadronic/models/im_r_matrix/include",
                    "processes/hadronic/models/inclxx/incl_physics/include",
                    "processes/hadronic/models/inclxx/utils/include",
                    "processes/hadronic/models/de_excitation/handler/include",
                    "processes/hadronic/models/pre_equilibrium/exciton_model/include",
                    "processes/hadronic/models/management/include",
                    "processes/hadronic/models/util/include",
                    "processes/hadronic/util/include",
                    "processes/management/include",
                    "track/include",
                    "intercoms/include"
                    ]
specificIncludeDirs "abla" = [ "geometry/management/include",
                    "geometry/volumes/include",
                    "global/HEPGeometry/include",
                    "global/HEPRandom/include",
                    "global/management/include",
                    "materials/include",
                    "particles/bosons/include",
                    "particles/hadrons/barions/include",
                    "particles/hadrons/ions/include",
                    "particles/hadrons/mesons/include",
                    "particles/leptons/include",
                    "particles/management/include",
                    "track/include",
                    "intercoms/include"
                    ]
specificIncludeDirs _ = [ "geometry/management/include",
                    "geometry/volumes/include",
                    "global/HEPGeometry/include",
                    "global/HEPRandom/include",
                    "global/management/include",
                    "materials/include",
                    "particles/bosons/include",
                    "particles/hadrons/barions/include",
                    "particles/hadrons/ions/include",
                    "particles/hadrons/mesons/include",
                    "particles/leptons/include",
                    "particles/management/include",
                    "processes/hadronic/cross_sections/include",
                    "processes/hadronic/management/include",
                    "processes/hadronic/models/binary_cascade/include",
                    "processes/hadronic/models/im_r_matrix/include",
                    "processes/hadronic/models/inclxx/incl_physics/include",
                    "processes/hadronic/models/inclxx/utils/include",
                    "processes/hadronic/models/de_excitation/handler/include",
                    "processes/hadronic/models/pre_equilibrium/exciton_model/include",
                    "processes/hadronic/models/management/include",
                    "processes/hadronic/models/util/include",
                    "processes/hadronic/util/include",
                    "processes/management/include",
                    "track/include",
                    "intercoms/include"
                    ]
