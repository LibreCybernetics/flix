/*
 * Copyright 2021 Benjamin Dahse
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

mod Fixpoint {

    use Fixpoint.Ast.{Datalog, Constraint, HeadPredicate, BodyPredicate, Polarity, Fixity, PrecedenceGraph}
    use Fixpoint.Ast.Datalog.{Datalog, Model, Join}
    use Fixpoint.Ast.PrecedenceGraph.PrecedenceGraph
    use Fixpoint.Ast.PrecedenceEdge.{WeakEdge, StrongEdge}
    use Fixpoint.Ast.Constraint.Constraint
    use Fixpoint.Ast.HeadPredicate.HeadAtom
    use Fixpoint.Ast.BodyPredicate.BodyAtom
    use Fixpoint.Shared.PredSym

    ///
    /// Compute a stratification with Ullman's algorithm.
    /// The Flix compiler is supposed to guarantee the existence of a stratification at this point.
    /// Initially, all IDB predicates are assigned to stratum 0.
    /// I.e. facts are ignored in the stratification.
    ///
    def stratify(d: Datalog[v]): Map[PredSym, Int32] = match d {
        case Datalog(_, rules) =>
            List.foldRight(match Constraint(HeadAtom(p, _, _), _) -> Map.insert(p, 0), Map#{}, rules) |>
            stratifyHelper(mkDepGraph(d))
        case Model(_) => Map#{} // Models contain only facts.
        case Join(d1, d2) => Map.unionWith(Int32.max, stratify(d1), stratify(d2))
    }

    def stratifyHelper(g: PrecedenceGraph, stf: Map[PredSym, Int32]): Map[PredSym, Int32] = match g {
        case PrecedenceGraph(xs) =>
            // The number of strata is bounded by the number of predicates
            // which is bounded by the number of edges in the precedence graph.
            let maxStratum = Set.size(xs);
            // Visit every edge and ensure the following:
            // 1. If (body, head) is a weak edge, then body belongs to a lower stratum
            // or the same stratum as head.
            // 2. If (body, head) is a strong edge, then body belongs to a strictly lower stratum
            // than head.
            let (newStf, changed) = Set.foldLeft(match (acc, changed) -> edge -> match edge {
                case WeakEdge(bodySym, headSym) =>
                    let bodyStratum = Map.getWithDefault(bodySym, 0, acc);
                    let headStratum = Map.getWithDefault(headSym, 0, acc);
                    if (bodyStratum > headStratum)
                        (Map.insert(headSym, bodyStratum, acc), true)
                    else
                        (acc, changed)
                case StrongEdge(bodySym, headSym) =>
                    let bodyStratum = Map.getWithDefault(bodySym, 0, acc);
                    let headStratum = Map.getWithDefault(headSym, 0, acc);
                    if (bodyStratum >= headStratum)
                        let newHeadStratum = bodyStratum + 1;
                        // If there are more strata than edges,
                        // the precedence graph must contain a strong cycle!
                        if (newHeadStratum > maxStratum)
                            bug!("Stratification error (strong cycle)")
                        else
                            (Map.insert(headSym, newHeadStratum, acc), true)
                    else
                        (acc, changed)
            }, (stf, false), xs);
            // Check if property 1 and 2 now holds for all edges.
            if (changed)
                stratifyHelper(g, newStf)
            else
                stf
    }

    def mkDepGraph(d: Datalog[v]): PrecedenceGraph = match d {
        case Datalog(_, rules) => List.fold(List.map(precedenceHelper, rules))
        case Model(_) => Monoid.empty()
        case Join(d1, d2) => Monoid.combine(mkDepGraph(d1), mkDepGraph(d2))
    }

    def precedenceHelper(cnst: Constraint[v]): PrecedenceGraph = match cnst {
        case Constraint(head, body) => List.fold(List.map(mkDepEdge(head), body))
    }

    ///
    /// Creates a singleton set with a strong or weak edge. Negatively bound atoms and
    /// fixed atoms create strong edges because the body predicate has to be in a strictly
    /// lower strata than the head. Positive, loose atoms create weak edges where the body
    /// has to be in the same strata as the head or lower.
    ///
    def mkDepEdge(dst: HeadPredicate[v], src: BodyPredicate[v]): PrecedenceGraph = match (dst, src) {
        case (HeadAtom(headSym, _, _), BodyAtom(bodySym, _, Polarity.Positive, Fixity.Loose, _)) =>
            PrecedenceGraph(Set#{WeakEdge(bodySym, headSym)})
        case (HeadAtom(headSym, _, _), BodyAtom(bodySym, _, _, _, _)) =>
            PrecedenceGraph(Set#{StrongEdge(bodySym, headSym)})
        case _ => PrecedenceGraph(Set#{})
    }
}
