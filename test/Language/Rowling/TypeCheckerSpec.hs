{-# LANGUAGE OverloadedStrings, OverloadedLists #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}
module Language.Rowling.TypeCheckerSpec (spec) where

import SpecHelper
import ClassyPrelude hiding (assert)
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as H
import Language.Rowling.Definitions.Expressions
import Language.Rowling.Definitions.Types
import Language.Rowling.TypeCheck.TypeChecker

-- | Shorthand for a repeatedly used function
twith :: TypeMap -> Expr -> Either EList Type
twith = typeWithBindingsN

can'tUnify :: Either EList Type -> IO ()
can'tUnify x = x `shouldHaveErr` "Can't unify types"

spec :: Spec
spec = do
  describe "primitive types" $ do
    it "should get type of literals" $ do
      typeExpr (Int 0) `shouldBeR` "Int"
      typeExpr (Float 0) `shouldBeR` "Float"
      typeExpr (String "hey there") `shouldBeR` "String"
      typeExpr "True" `shouldBeR` "Bool"
      typeExpr "False" `shouldBeR` "Bool"

  describe "lists" $ do
    it "should type lists" $ do
      typeExpr [Int 0, Int 1] `shouldBeR` TApply "List" "Int"
    it "should fail if not all are same type" $ do
      can'tUnify (typeExpr [Int 0, Float 1])

  describe "functions" $ do
    it "should type functions" $ do
      typeExprN (Lambda "x" "x") `shouldBeR` "a" ==> "a"
      typeExprN (Lambda "x" $ Lambda "y" $ Apply "y" "x")
        `shouldBeR`
        "a" ==> ("a" ==> "b") ==> "b"

  describe "applications" $ do
    it "should type applications" $ do
      typeExpr (Apply (Lambda "x" "x") (Int 1)) `shouldBeR` "Int"
      typeExpr (Apply (Lambda "x" "x") [Int 1])
        `shouldBeR` TApply "List" "Int"
      typeExpr (Apply (Lambda "x" ["x"]) (Float 1))
        `shouldBeR` TApply "List" "Float"

  describe "lets" $ do
    it "should type let statements" $ do
      typeExpr (Let "foo" (Int 1) "foo") `shouldBeR` "Int"
      typeExprN (Lambda "x" $ Let "y" "x" "y") `shouldBeR` "a" ==> "a"
      typeExprN (Lambda "x" $ Let "y" (Int 1) "y") `shouldBeR` "a" ==> "Int"
      typeExpr (Let "id" (Lambda "x" "x") (Apply "id" (Int 1)))
        `shouldBeR` "Int"

  describe "case statements" $ do
    it "should error if there are no alternatives" $ do
      twith [("x", "Int")] (Case "x" []) `shouldHaveErr` "No alternatives"

    it "should error if pattern types don't match test type" $ do
      let t = twith [("x", "Float")]
      can'tUnify (t (Case "x" [(Int 0, Int 1)]))
      can'tUnify (t (Case "x" [(Float 0, Int 1), (Int 1, Int 2)]))

    it "should error if result types don't match each other" $ do
      let t = twith [("x", "Int")]
      can'tUnify (t (Case "x" [(Int 0, Float 1), (Int 1, Int 0)]))

    it "should type simple case expressions" $ do
      let t = twith [("x", "Int")]
      t (Case "x" [(Int 0, Float 1)]) `shouldBeR` "Float"
      t (Case "x" [(Int 0, Float 1), (Int 1, Float 2)]) `shouldBeR` "Float"
      t (Case "x" [(Int 0, Int 1), ("q", "q")]) `shouldBeR` "Int"

    it "should handle records in case expressions" $ do
      -- This tests that the following typing holds:
      -- λ(x: 1, y: y) -> y.z : (x: Int, y: (z: a | b) | c) -> a
      let pat = Record [("x", Int 1), ("y", "y")]
          res = "y" `Dot` "z"
          trec1 = tRecord' [("z", "a")] "b"
          trec2 = tRecord' [("x", "Int"), ("y", trec1)] "c"
      let input = Lambda "q" $ Case "q" [(pat, res)]
      typeExprN input `shouldBeR` trec2 ==> "a"

    it "should type constructed expressions in case expressions" $ do
      let case_ = Case "x" [(Apply "Some" "y", binary "y" "+" (Int 1)),
                            ("None", Int 0)]
          input = Lambda "x" $ case_
      typeExpr input `shouldBeR` TApply "Maybe" "Int" ==> "Int"

    it "should handle list patterns" $ do
      let input = Lambda "x" $ Case "x" [([Int 1, Int 2], Int 3),
                                         (["y", "z"], binary "y" "+" "z")]
          output = TApply "List" "Int" ==> "Int"
      typeExpr input `shouldBeR` output

  describe "builtins" $ do
    describe "binary operators" $ do
      it "should type check addition" $ do
        typeExpr (binary (Int 1) "+" (Int 2)) `shouldBeR` "Int"

    describe "constructors" $ do
      it "should recognize maybes" $ do
        typeExprN "None" `shouldBeR` TApply "Maybe" "a"
        typeExpr (Apply "Some" (Int 1)) `shouldBeR` TApply "Maybe" "Int"
