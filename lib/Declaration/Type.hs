module Declaration.Type where

import "rio" RIO

import "freer-simple" Control.Monad.Freer        (Eff, Members)
import "freer-simple" Control.Monad.Freer.Error  (Error)
import "prettyprinter" Data.Text.Prettyprint.Doc
    ( Doc
    , colon
    , indent
    , line
    , (<+>)
    )

import qualified "purescript" Language.PureScript

import qualified "this" Annotation
import qualified "this" Comment
import qualified "this" Kind
import qualified "this" Name
import qualified "this" Type
import qualified "this" Variations

data Type a
  = Type !Comment.Comments !(Name.Common a) !(Type.Type a)
  deriving (Functor, Show)

fromPureScript ::
  ( Members
    '[ Error Kind.InferredKind
     , Error Name.InvalidCommon
     , Error Name.Missing
     , Error Type.InferredConstraintData
     , Error Type.InferredForallWithSkolem
     , Error Type.InferredSkolem
     , Error Type.InferredType
     , Error Type.InfixTypeNotTypeOp
     , Error Type.PrettyPrintForAll
     , Error Type.PrettyPrintFunction
     , Error Type.PrettyPrintObject
     ]
    e
  ) =>
  Language.PureScript.TypeDeclarationData ->
  Eff e (Type Annotation.Unannotated)
fromPureScript = \case
  Language.PureScript.TypeDeclarationData (_, comments') ident type'' -> do
    let comments = Comment.comments comments'
    name <- Name.common ident
    type' <- Type.fromPureScript type''
    pure (Type comments name type')

doc :: Type Annotation.Normalized -> Variations.Variations (Doc a)
doc = \case
  Type comments name type' ->
    Variations.Variations { Variations.multiLine, Variations.singleLine }
    where
    multiLine =
      Comment.docFromComments comments
        <> Name.docFromCommon name <+> colon <> colon
        <> line
        <> indent 2 (Variations.multiLine $ Type.doc type')
    singleLine =
      Comment.docFromComments comments
        <> Name.docFromCommon name <+> colon <> colon
        <+> Variations.singleLine (Type.doc type')

normalize :: Type a -> Type Annotation.Normalized
normalize = \case
  Type comments name type' ->
    Type comments (Annotation.None <$ name) (Type.normalize type')
