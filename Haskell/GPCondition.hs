module GPCondition where

import ParseLib
import ParseRule
import ParseProgram
import ParseGraph
import GPSyntax
import ProcessAst
import LabelMatch
import GraphMatch
import Graph
import ExAr
import Data.List
import Data.Maybe

-- Test data
testastrule :: AstRule
testastrule = (AstRule "rule1" 
               [("i",IntVar),("l",ListVar)] 
              (AstRuleGraph [RuleNode "n1" False (RuleLabel [Var ("i",ListVar)] Uncoloured),
                             RuleNode "n2" False (RuleLabel [Var ("l",ListVar)] Uncoloured)]
                            [RuleEdge False "n1" "n2" (RuleLabel [] Uncoloured)],
               AstRuleGraph [RuleNode "n1" False (RuleLabel [Var ("i",ListVar)] Uncoloured),
                             RuleNode "n2" False (RuleLabel [Var ("l",ListVar),Var ("i",ListVar)] Uncoloured)] 
                            [RuleEdge False "n1" "n2" (RuleLabel [] Uncoloured)])
              ["n1","n2"] 
              (Edge "n1" "n2" Nothing) 
              "true")

testLHS :: AstRuleGraph
testLHS = (AstRuleGraph [RuleNode "n1" False (RuleLabel [Var ("i",ListVar)] Uncoloured),
                         RuleNode "n2" False (RuleLabel [Var ("l",ListVar)] Uncoloured)]
                        [RuleEdge False "n1" "n2" (RuleLabel [] Uncoloured)])

testhg :: AstHostGraph
testhg = AstHostGraph 
        [HostNode "n1" False (HostLabel [Int 1] Uncoloured),
         HostNode "n2" False (HostLabel [Str "hello"] Uncoloured),
         HostNode "n3" False (HostLabel [Int 1, Int 2] Uncoloured)]
        [HostEdge "n1" "n2" (HostLabel [] Uncoloured),
         HostEdge "n1" "n3" (HostLabel [] Uncoloured)]

testtab :: SymbolTable
testtab = makeTable slist

slist :: SymbolList
slist = [("i", Symbol (Var_S IntVar False) "Global" "r1"),
         ("l", Symbol (Var_S ListVar False) "Global" "r1")]


lhs :: RuleGraph
lhs = fst $ makeRuleGraph testLHS "Global" "r1" testtab

host :: HostGraph
host = makeHostGraph testhg

testmorphisms :: [GraphMorphism]
testmorphisms =  matchGraphs host lhs





getHostNodeId :: HostGraph -> NodeName -> NodeId
getHostNodeId g id = case candidates of
        [] -> error $ "ID " ++ id ++ " not found"
        [nid] -> nid
        _  -> error $ "Duplicate ID found! Eep!"
    where
        candidates = filter (matchID . nLabel g) $ allNodes g
        matchID :: HostNode -> Bool
        matchID (HostNode i _ _) = i == id

getRuleNodeId :: RuleGraph -> NodeName -> NodeId
getRuleNodeId r id = case candidates of
        [] -> error $ "ID " ++ id ++ " not found"
        [nid] -> nid
        _  -> error $ "Duplicate ID found! Eep!"
    where
        candidates = filter (matchID . nLabel r) $ allNodes r
        matchID :: RuleNode -> Bool
        matchID (RuleNode i _ _) = i == id

getNodeName :: HostGraph -> NodeId -> NodeName
getNodeName g nid = case maybeNLabel g nid of
        Nothing -> error "Fail!"
        Just ( HostNode id _ _ ) -> id

-- type Environment = Subst ID [HostAtom]

-- Given a graph morphism (containing a variable-value mapping) and a host graph,
-- a rule label is transformed into a host label (list of constants) by evaluating
-- any operators (degree, length) and substituting variables for their values
-- according to the morphism.
labelEval :: GraphMorphism -> HostGraph -> RuleGraph -> RuleLabel -> HostLabel
labelEval m g r (RuleLabel list col) = HostLabel (concatMap (atomEval m g r) list) col

atomEval :: GraphMorphism -> HostGraph -> RuleGraph -> RuleAtom -> [HostAtom]
atomEval m@(GM env _ _) g r a = case a of
   -- TODO: error check
   Var (name, gpType) -> fromJust $ lookup name env 
   Val ha -> [ha]
   -- Degree operators assume node exists in the morphism/LHS graph.
   Indeg node -> [Int $ intExpEval m g r a]
   Outdeg node -> [Int $ intExpEval m g r a]
   Llength list -> [Int $ length list]
   Slength exp -> [Int $ length $ stringExpEval env exp]
   Neg exp -> [Int $ intExpEval m g r a]
   Plus exp1 exp2 -> [Int $ intExpEval m g r a]
   Minus exp1 exp2 -> [Int $ intExpEval m g r a]
   Times exp1 exp2 -> [Int $ intExpEval m g r a]
   Div exp1 exp2 ->  [Int $ intExpEval m g r a]
   exp@(Concat exp1 exp2) -> [Str $ stringExpEval env exp]

-- Expects a RuleAtom representing an integer expression. 
intExpEval :: GraphMorphism -> HostGraph -> RuleGraph -> RuleAtom -> Int
intExpEval m@(GM env nms _) g r a = case a of
   Var (name, IntVar) -> let Just [Int i] = lookup name env in i
   Val (Int i) -> i
   -- TODO: Error checking of degree operators.
   Indeg node -> let Just hnode = lookup (getRuleNodeId r node) nms 
                 in length $ inEdges g hnode
   Outdeg node -> let Just hnode = lookup (getRuleNodeId r node) nms 
                  in length $ outEdges g hnode
   Llength list -> length list
   Slength exp -> length $ stringExpEval env exp
   Neg exp -> 0 - intExpEval m g r exp
   Plus exp1 exp2 -> intExpEval m g r exp1 + intExpEval m g r exp2
   Minus exp1 exp2 -> intExpEval m g r exp1 - intExpEval m g r exp2
   Times exp1 exp2 -> intExpEval m g r exp1 * intExpEval m g r exp2
   -- TODO: handle division by 0
   Div exp1 exp2 -> intExpEval m g r exp1 `div` intExpEval m g r exp2
   _ -> error "Not an integer expression."

-- Expects a RuleAtom representing a string expression. 
stringExpEval :: Environment -> RuleAtom -> String
stringExpEval env a = case a of
   Var (name, ChrVar) -> let Just [Chr c] = lookup name env in "c"
   Var (name, StrVar) -> let Just [Str s] = lookup name env in s
   Val (Chr c) -> "c"
   Val (Str s) -> s 
   Concat exp1 exp2 -> stringExpEval env exp1 ++ stringExpEval env exp2
   _ -> error "Not a string expression."


conditionEval :: Condition -> GraphMorphism -> HostGraph -> RuleGraph -> Bool
conditionEval c m@(GM env nms _) g r = 
  case c of
     NoCondition -> True
     TestInt name -> 
        let var = lookup name env
        in
           case var of
               Nothing       -> False
               Just ([Int _]) -> True
               _             -> False

     TestChr name -> 
        let var = lookup name env
        in
           case var of
               Nothing         -> False
               Just ([Chr _]) -> True
               _               -> False                         

     TestStr name -> 
        let var = lookup name env
        in
           case var of
               Nothing        -> False
               Just ([Str _]) -> True
               _              -> False

     TestAtom name -> 
        let var = lookup name env
        in
           case var of
               Nothing      -> False
               Just ([_])   -> True
               _            -> False

     Edge src tgt maybeLabel ->   
        -- Bug: if label is Nothing, should only test the existence of an
        --      edge between the two nodes.
        let label = fromMaybe (RuleLabel [] Uncoloured) maybeLabel
            hsrc = lookup (getRuleNodeId r src) nms
            htgt = lookup (getRuleNodeId r tgt) nms
            hlabel = labelEval m g r label
        in
           if (isNothing hsrc || isNothing htgt) 
              then False
              else foldr (labelCompare hlabel) False (joiningEdges g (fromJust hsrc) (fromJust htgt))
        where 
        -- Should be RuleLabel. Use eval functions.
        -- labelCompare :: (HostLabel -> EdgeId -> Bool -> Bool)
           labelCompare _ _ True = True
           labelCompare hlabel e False = 
              case (maybeELabel g e) of
                 Nothing     -> False
                 Just label  -> label == hlabel

     Eq l1 l2 -> and $ zipWith (==) (concatMap (atomEval m g r) l1) (concatMap (atomEval m g r) l2)

     NEq l1 l2 -> or $ zipWith (/=) (concatMap (atomEval m g r) l1) (concatMap (atomEval m g r) l2)

     -- GP2 semantics requires atoms in relational conditions to be integer 
     -- expressions. 

     Greater a1 a2 -> intExpEval m g r a1 > intExpEval m g r a2
 
     GreaterEq a1 a2 -> intExpEval m g r a1 >= intExpEval m g r a2
 
     Less a1 a2 -> intExpEval m g r a1 < intExpEval m g r a2

     LessEq a1 a2 -> intExpEval m g r a1 <= intExpEval m g r a2

     Not cond -> not $ conditionEval cond m g r 
 
     Or cond1 cond2 -> (conditionEval cond1 m g r) || (conditionEval cond2 m g r)

     And cond1 cond2 -> (conditionEval cond1 m g r) && (conditionEval cond2 m g r)




