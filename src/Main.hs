module Main where

import "protolude" Protolude

import "base" Data.List                                      (span)
import "prettyprinter" Data.Text.Prettyprint.Doc
    ( Doc
    , LayoutOptions
    , defaultLayoutOptions
    , enclose
    , indent
    , layoutSmart
    , line
    , parens
    , pretty
    , sep
    , tupled
    , vsep
    , (<+>)
    )
import "prettyprinter" Data.Text.Prettyprint.Doc.Render.Text (renderIO)
import "purescript" Language.PureScript
    ( Comment(BlockComment, LineComment)
    , DataDeclType(Data, Newtype)
    , Declaration(DataBindingGroupDeclaration, DataDeclaration, ImportDeclaration)
    , DeclarationRef(KindRef, ModuleRef, ReExportRef, TypeClassRef, TypeInstanceRef, TypeOpRef, TypeRef, ValueOpRef, ValueRef)
    , ImportDeclarationType(Explicit, Hiding, Implicit)
    , Kind
    , Module(Module)
    , ModuleName
    , ProperName
    , ProperNameType(ConstructorName)
    , isImportDecl
    , parseModuleFromFile
    , prettyPrintKind
    , prettyPrintType
    , runIdent
    , runModuleName
    , runProperName
    , showOp
    )
import "microlens-platform" Lens.Micro.Platform              (Lens', view)
import "optparse-applicative" Options.Applicative
    ( Parser
    , ParserInfo
    , argument
    , execParser
    , fullDesc
    , header
    , help
    , helper
    , info
    , maybeReader
    , metavar
    , progDesc
    )
import "path" Path
    ( Abs
    , File
    , Path
    , fromAbsFile
    , parseAbsFile
    )

import qualified "purescript" Language.PureScript

main :: IO ()
main = do
  envArgs <- execParser argsInfo
  let envPrettyPrintConfig =
        PrettyPrintConfig { layoutOptions = defaultLayoutOptions }
  runApp Env { envArgs, envPrettyPrintConfig } purty

purty :: (HasArgs env, HasPrettyPrintConfig env) => App env ()
purty = do
  Args { filePath } <- view argsL
  PrettyPrintConfig { layoutOptions } <- view prettyPrintConfigL
  contents <- liftIO $ readFile (fromAbsFile filePath)
  case parseModuleFromFile identity (fromAbsFile filePath, contents) of
    Left error -> do
      putErrText "Problem parsing module"
      putErrText (show error)
    Right (file, m) -> do
      putText $ "parsed " <> toS file
      liftIO $ renderIO stdout $ layoutSmart layoutOptions (docFromModule m)

docFromModule :: Module -> Doc a
docFromModule (Module _ comments name declarations' exports) =
  foldMap docFromComment comments
    <> "module"
    <+> pretty (runModuleName name)
    <+> foldMap docFromExports exports
    <+> "where"
    <> line
    <> line
    <> docFromImports imports
    <> line
    <> line
    <> docFromDeclarations declarations
    <> line
  where
  (imports, declarations) = span isImportDecl declarations'

docFromComment :: Comment -> Doc a
docFromComment = \case
  BlockComment comment -> enclose "{-" "-}" (pretty comment) <> line
  LineComment comment -> "--" <> pretty comment <> line

docFromDataConstructors :: [(ProperName 'ConstructorName, [Language.PureScript.Type])] -> Doc a
docFromDataConstructors =
  vsep . zipWith (<+>) ("=" : repeat "|") . map docFromDataConstructor

docFromDataConstructor :: (ProperName 'ConstructorName, [Language.PureScript.Type]) -> Doc a
docFromDataConstructor (name, types) =
  pretty (runProperName name) <+> sep (map (pretty . prettyPrintType) types)

docFromDataType :: DataDeclType -> Doc a
docFromDataType = \case
  Data -> "data"
  Newtype -> "newtype"

docFromDeclarations :: [Declaration] -> Doc a
docFromDeclarations = vsep . map docFromDeclaration

docFromDeclaration :: Declaration -> Doc a
docFromDeclaration = \case
  DataBindingGroupDeclaration (declarations) ->
    vsep (toList $ map docFromDeclaration declarations)
  DataDeclaration _ dataType name parameters constructors ->
    docFromDataType dataType
      <+> pretty (runProperName name)
      <+> foldMap docFromParameter parameters
      <> line
      <> indent 2 (docFromDataConstructors constructors)
  _ -> mempty

docFromExports :: [DeclarationRef] -> Doc a
docFromExports = tupled . map docFromExport

docFromExport :: DeclarationRef -> Doc a
docFromExport = \case
  KindRef _ name -> "kind" <+> pretty (runProperName name)
  ModuleRef _ name -> "module" <+> pretty (runModuleName name)
  ReExportRef _ _ _ -> mempty
  TypeRef _ name constructors ->
    -- N.B. `Nothing` means everything
    pretty (runProperName name) <> maybe "(..)" docFromConstructors constructors
  TypeClassRef _ name -> "class" <+> pretty (runProperName name)
  TypeInstanceRef _ _ -> mempty
  TypeOpRef _ name -> "type" <+> pretty (showOp name)
  ValueRef _ ident -> pretty (runIdent ident)
  ValueOpRef _ name -> pretty (showOp name)

docFromConstructors :: [ProperName 'ConstructorName] -> Doc a
docFromConstructors [] = mempty
docFromConstructors constructors =
  tupled $ map (pretty . runProperName) constructors

docFromKind :: Kind -> Doc a
docFromKind = pretty . prettyPrintKind

docFromImports :: [Declaration] -> Doc a
docFromImports = vsep . map docFromImport

docFromImport :: Declaration -> Doc a
docFromImport = \case
  ImportDeclaration _ name importType qualified ->
    "import"
      <+> pretty (runModuleName name)
      <+> docFromImportType importType
      <+> foldMap docFromImportQualified qualified
  _ -> mempty

docFromImportQualified :: ModuleName -> Doc a
docFromImportQualified name = "as" <+> pretty (runModuleName name)

docFromImportType :: ImportDeclarationType -> Doc a
docFromImportType = \case
  Explicit declarationRefs -> docFromExports declarationRefs
  Hiding declarationRefs -> "hiding" <+> docFromExports declarationRefs
  Implicit -> mempty

docFromParameter :: (Text, Maybe Kind) -> Doc a
docFromParameter (parameter, Nothing) = pretty parameter
docFromParameter (parameter, Just k) =
  parens (pretty parameter <+> "::" <+> docFromKind k)

data Args
  = Args
    { filePath :: !(Path Abs File)
    }

class HasArgs env where
  argsL :: Lens' env Args

args :: Parser Args
args =
  Args
    <$> argument
      (maybeReader parseAbsFile)
      ( help "PureScript file to pretty print"
      <> metavar "FILE"
      )

argsInfo :: ParserInfo Args
argsInfo =
  info
    (helper <*> args)
    ( fullDesc
    <> progDesc "Pretty print a PureScript file"
    <> header "purty - A PureScript pretty-printer"
    )

data PrettyPrintConfig
  = PrettyPrintConfig
    { layoutOptions :: !LayoutOptions
    }

class HasPrettyPrintConfig env where
  prettyPrintConfigL :: Lens' env PrettyPrintConfig

data Env
  = Env
    { envArgs              :: !Args
    , envPrettyPrintConfig :: !PrettyPrintConfig
    }

class HasEnv env where
  envL :: Lens' env Env

instance HasArgs Env where
  argsL f env = (\envArgs -> env { envArgs }) <$> f (envArgs env)

instance HasEnv Env where
  envL = identity

instance HasPrettyPrintConfig Env where
  prettyPrintConfigL f env = (\envPrettyPrintConfig -> env { envPrettyPrintConfig }) <$> f (envPrettyPrintConfig env)

-- Locally defined rio since dependencies are wild.
newtype App r a
  = App { unApp :: ReaderT r IO a }
  deriving
    ( Applicative
    , Functor
    , Monad
    , MonadIO
    , MonadReader r
    )

runApp :: r -> App r a -> IO a
runApp r (App x) = runReaderT x r
