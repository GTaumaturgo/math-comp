(* (c) Copyright 2006-2016 Microsoft Corporation and Inria.                  *)
(* Distributed under the terms of CeCILL-B.                                  *)
From mathcomp Require Import ssreflect ssrfun ssrbool eqtype ssrnat seq.

(******************************************************************************)
(*    The basic theory of paths over an eqType; this file is essentially a    *)
(* complement to seq.v. Paths are non-empty sequences that obey a progression *)
(* relation. They are passed around in three parts: the head and tail of the  *)
(* sequence, and a proof of (boolean) predicate asserting the progression.    *)
(* This "exploded" view is rarely embarrassing, as the first two parameters   *)
(* are usually inferred from the type of the third; on the contrary, it saves *)
(* the hassle of constantly constructing and destructing a dependent record.  *)
(*    We define similarly cycles, for which we allow the empty sequence,      *)
(* which represents a non-rooted empty cycle; by contrast, the "empty" path   *)
(* from a point x is the one-item sequence containing only x.                 *)
(*   We allow duplicates; uniqueness, if desired (as is the case for several  *)
(* geometric constructions), must be asserted separately. We do provide       *)
(* shorthand, but only for cycles, because the equational properties of       *)
(* "path" and "uniq" are unfortunately  incompatible (esp. wrt "cat").        *)
(*    We define notations for the common cases of function paths, where the   *)
(* progress relation is actually a function. In detail:                       *)
(*   path e x p == x :: p is an e-path [:: x_0; x_1; ... ; x_n], i.e., we     *)
(*                 e x_i x_{i+1} for all i < n. The path x :: p starts at x   *)
(*                 and ends at last x p.                                      *)
(*  fpath f x p == x :: p is an f-path, where f is a function, i.e., p is of  *)
(*                 the form [:: f x; f (f x); ...]. This is just a notation   *)
(*                 for path (frel f) x p.                                     *)
(*   sorted e s == s is an e-sorted sequence: either s = [::], or s = x :: p  *)
(*                 is an e-path (this is oten used with e = leq or ltn).      *)
(*    cycle e c == c is an e-cycle: either c = [::], or c = x :: p with       *)
(*                 x :: (rcons p x) an e-path.                                *)
(*   fcycle f c == c is an f-cycle, for a function f.                         *)
(* traject f x n == the f-path of size n starting at x                        *)
(*              := [:: x; f x; ...; iter n.-1 f x]                            *)
(* looping f x n == the f-paths of size greater than n starting at x loop     *)
(*                 back, or, equivalently, traject f x n contains all         *)
(*                 iterates of f at x.                                        *)
(* merge e s1 s2 == the e-sorted merge of sequences s1 and s2: this is always *)
(*                 a permutation of s1 ++ s2, and is e-sorted when s1 and s2  *)
(*                 are and e is total.                                        *)
(*     sort e s == a permutation of the sequence s, that is e-sorted when e   *)
(*                 is total (computed by a merge sort with the merge function *)
(*                 above).  This sort function is also designed to be stable. *)
(*   mem2 s x y == x, then y occur in the sequence (path) s; this is          *)
(*                 non-strict: mem2 s x x = (x \in s).                        *)
(*     next c x == the successor of the first occurrence of x in the sequence *)
(*                 c (viewed as a cycle), or x if x \notin c.                 *)
(*     prev c x == the predecessor of the first occurrence of x in the        *)
(*                 sequence c (viewed as a cycle), or x if x \notin c.        *)
(*    arc c x y == the sub-arc of the sequece c (viewed as a cycle) starting  *)
(*                 at the first occurrence of x in c, and ending just before  *)
(*                 the next ocurrence of y (in cycle order); arc c x y        *)
(*                 returns an unspecified sub-arc of c if x and y do not both *)
(*                 occur in c.                                                *)
(*  ucycle e c <-> ucycleb e c (ucycle e c is a Coercion target of type Prop) *)
(* ufcycle f c <-> c is a simple f-cycle, for a function f.                   *)
(*  shorten x p == the tail a duplicate-free subpath of x :: p with the same  *)
(*                 endpoints (x and last x p), obtained by removing all loops *)
(*                 from x :: p.                                               *)
(* rel_base e e' h b <-> the function h is a functor from relation e to       *)
(*                 relation e', EXCEPT at points whose image under h satisfy  *)
(*                 the "base" predicate b:                                    *)
(*                    e' (h x) (h y) = e x y UNLESS b (h x) holds             *)
(*                 This is the statement of the side condition of the path    *)
(*                 functorial mapping lemma map_path.                         *)
(* fun_base f f' h b <-> the function h is a functor from function f to f',   *)
(*                 except at the preimage of predicate b under h.             *)
(* We also provide three segmenting dependently-typed lemmas (splitP, splitPl *)
(* and splitPr) whose elimination split a path x0 :: p at an internal point x *)
(* as follows:                                                                *)
(*  - splitP applies when x \in p; it replaces p with (rcons p1 x ++ p2), so  *)
(*    that x appears explicitly at the end of the left part. The elimination  *)
(*    of splitP will also simultaneously replace take (index x p) with p1 and *)
(*    drop (index x p).+1 p with p2.                                          *)
(*  - splitPl applies when x \in x0 :: p; it replaces p with p1 ++ p2 and     *)
(*    simulaneously generates an equation x = last x0 p.                      *)
(*  - splitPr applies when x \in p; it replaces p with (p1 ++ x :: p2), so x  *)
(*    appears explicitly at the start of the right part.                      *)
(* The parts p1 and p2 are computed using index/take/drop in all cases, but   *)
(* only splitP attemps to subsitute the explicit values. The substitution of  *)
(* p can be deferred using the dependent equation generation feature of       *)
(* ssreflect, e.g.: case/splitPr def_p: {1}p / x_in_p => [p1 p2] generates    *)
(* the equation p = p1 ++ p2 instead of performing the substitution outright. *)
(*   Similarly, eliminating the loop removal lemma shortenP simultaneously    *)
(* replaces shorten e x p with a fresh constant p', and last x p with         *)
(* last x p'.                                                                 *)
(*   Note that although all "path" functions actually operate on the          *)
(* underlying sequence, we provide a series of lemmas that define their       *)
(* interaction with thepath and cycle predicates, e.g., the cat_path equation *)
(* can be used to split the path predicate after splitting the underlying     *)
(* sequence.                                                                  *)
(******************************************************************************)

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Section Paths.

Variables (n0 : nat) (T : Type).

Section Path.

Variables (x0_cycle : T) (e : rel T).

Fixpoint path x (p : seq T) :=
  if p is y :: p' then e x y && path y p' else true.

Lemma cat_path x p1 p2 : path x (p1 ++ p2) = path x p1 && path (last x p1) p2.
Proof. by elim: p1 x => [|y p1 Hrec] x //=; rewrite Hrec -!andbA. Qed.

Lemma rcons_path x p y : path x (rcons p y) = path x p && e (last x p) y.
Proof. by rewrite -cats1 cat_path /= andbT. Qed.

Lemma pathP x p x0 :
  reflect (forall i, i < size p -> e (nth x0 (x :: p) i) (nth x0 p i))
          (path x p).
Proof.
elim: p x => [|y p IHp] x /=; first by left.
apply: (iffP andP) => [[e_xy /IHp e_p [] //] | e_p].
by split; [apply: (e_p 0) | apply/(IHp y) => i; apply: e_p i.+1].
Qed.

Definition cycle p := if p is x :: p' then path x (rcons p' x) else true.

Lemma cycle_path p : cycle p = path (last x0_cycle p) p.
Proof. by case: p => //= x p; rewrite rcons_path andbC. Qed.

Lemma rot_cycle p : cycle (rot n0 p) = cycle p.
Proof.
case: n0 p => [|n] [|y0 p] //=; first by rewrite /rot /= cats0.
rewrite /rot /= -{3}(cat_take_drop n p) -cats1 -catA cat_path.
case: (drop n p) => [|z0 q]; rewrite /= -cats1 !cat_path /= !andbT andbC //.
by rewrite last_cat; repeat bool_congr.
Qed.

Lemma rotr_cycle p : cycle (rotr n0 p) = cycle p.
Proof. by rewrite -rot_cycle rotrK. Qed.

End Path.

Lemma eq_path e e' : e =2 e' -> path e =2 path e'.
Proof. by move=> ee' x p; elim: p x => //= y p IHp x; rewrite ee' IHp. Qed.

Lemma eq_cycle e e' : e =2 e' -> cycle e =1 cycle e'.
Proof. by move=> ee' [|x p] //=; apply: eq_path. Qed.

Lemma sub_path e e' : subrel e e' -> forall x p, path e x p -> path e' x p.
Proof. by move=> ee' x p; elim: p x => //= y p IHp x /andP[/ee'-> /IHp]. Qed.

Lemma rev_path e x p :
  path e (last x p) (rev (belast x p)) = path (fun z => e^~ z) x p.
Proof.
elim: p x => //= y p IHp x; rewrite rev_cons rcons_path -{}IHp andbC.
by rewrite -(last_cons x) -rev_rcons -lastI rev_cons last_rcons.
Qed.

End Paths.

Arguments pathP {T e x p}.

Section HomoPath.

Variables (T T' : Type) (f : T -> T') (leT : rel T) (leT' : rel T').

Lemma homo_path x s : {homo f : x y / leT x y >-> leT' x y} ->
  path leT x s -> path leT' (f x) (map f s).
Proof.
move=> f_homo; elim: s => //= y s IHs in x *.
by move=> /andP[le_xy path_y_s]; rewrite f_homo//= IHs.
Qed.

Lemma mono_path x s : {mono f : x y / leT x y >-> leT' x y} ->
  path leT' (f x) (map f s) = path leT x s.
Proof. by move=> f_mon; elim: s => //= y s IHs in x *; rewrite f_mon IHs. Qed.

End HomoPath.

Arguments homo_path {T T' f leT leT' x s}.
Arguments mono_path {T T' f leT leT' x s}.

Section EqPath.

Variables (n0 : nat) (T : eqType) (x0_cycle : T) (e : rel T).
Implicit Type p : seq T.

Variant split x : seq T -> seq T -> seq T -> Type :=
  Split p1 p2 : split x (rcons p1 x ++ p2) p1 p2.

Lemma splitP p x (i := index x p) :
  x \in p -> split x p (take i p) (drop i.+1 p).
Proof.
move=> p_x; have lt_ip: i < size p by rewrite index_mem.
by rewrite -{1}(cat_take_drop i p) (drop_nth x lt_ip) -cat_rcons nth_index.
Qed.

Variant splitl x1 x : seq T -> Type :=
  Splitl p1 p2 of last x1 p1 = x : splitl x1 x (p1 ++ p2).

Lemma splitPl x1 p x : x \in x1 :: p -> splitl x1 x p.
Proof.
rewrite inE; case: eqP => [->| _ /splitP[]]; first by rewrite -(cat0s p).
by split; apply: last_rcons.
Qed.

Variant splitr x : seq T -> Type :=
  Splitr p1 p2 : splitr x (p1 ++ x :: p2).

Lemma splitPr p x : x \in p -> splitr x p.
Proof. by case/splitP=> p1 p2; rewrite cat_rcons. Qed.

Fixpoint next_at x y0 y p :=
  match p with
  | [::] => if x == y then y0 else x
  | y' :: p' => if x == y then y' else next_at x y0 y' p'
  end.

Definition next p x := if p is y :: p' then next_at x y y p' else x.

Fixpoint prev_at x y0 y p :=
  match p with
  | [::]     => if x == y0 then y else x
  | y' :: p' => if x == y' then y else prev_at x y0 y' p'
  end.

Definition prev p x := if p is y :: p' then prev_at x y y p' else x.

Lemma next_nth p x :
  next p x = if x \in p then
               if p is y :: p' then nth y p' (index x p) else x
             else x.
Proof.
case: p => //= y0 p.
elim: p {2 3 5}y0 => [|y' p IHp] y /=; rewrite (eq_sym y) inE;
  by case: ifP => // _; apply: IHp.
Qed.

Lemma prev_nth p x :
  prev p x = if x \in p then
               if p is y :: p' then nth y p (index x p') else x
             else x.
Proof.
case: p => //= y0 p; rewrite inE orbC.
elim: p {2 5}y0 => [|y' p IHp] y; rewrite /= ?inE // (eq_sym y').
by case: ifP => // _; apply: IHp.
Qed.

Lemma mem_next p x : (next p x \in p) = (x \in p).
Proof.
rewrite next_nth; case p_x: (x \in p) => //.
case: p (index x p) p_x => [|y0 p'] //= i _; rewrite inE.
have [lt_ip | ge_ip] := ltnP i (size p'); first by rewrite orbC mem_nth.
by rewrite nth_default ?eqxx.
Qed.

Lemma mem_prev p x : (prev p x \in p) = (x \in p).
Proof.
rewrite prev_nth; case p_x: (x \in p) => //; case: p => [|y0 p] // in p_x *.
by apply mem_nth; rewrite /= ltnS index_size.
Qed.

(* ucycleb is the boolean predicate, but ucycle is defined as a Prop *)
(* so that it can be used as a coercion target. *)
Definition ucycleb p := cycle e p && uniq p.
Definition ucycle p : Prop := cycle e p && uniq p.

(* Projections, used for creating local lemmas. *)
Lemma ucycle_cycle p : ucycle p -> cycle e p.
Proof. by case/andP. Qed.

Lemma ucycle_uniq p : ucycle p -> uniq p.
Proof. by case/andP. Qed.

Lemma next_cycle p x : cycle e p -> x \in p -> e x (next p x).
Proof.
case: p => //= y0 p; elim: p {1 3 5}y0 => [|z p IHp] y /=; rewrite inE.
  by rewrite andbT; case: (x =P y) => // ->.
by case/andP=> eyz /IHp; case: (x =P y) => // ->.
Qed.

Lemma prev_cycle p x : cycle e p -> x \in p -> e (prev p x) x.
Proof.
case: p => //= y0 p; rewrite inE orbC.
elim: p {1 5}y0 => [|z p IHp] y /=; rewrite ?inE.
  by rewrite andbT; case: (x =P y0) => // ->.
by case/andP=> eyz /IHp; case: (x =P z) => // ->.
Qed.

Lemma rot_ucycle p : ucycle (rot n0 p) = ucycle p.
Proof. by rewrite /ucycle rot_uniq rot_cycle. Qed.

Lemma rotr_ucycle p : ucycle (rotr n0 p) = ucycle p.
Proof. by rewrite /ucycle rotr_uniq rotr_cycle. Qed.

(* The "appears no later" partial preorder defined by a path. *)

Definition mem2 p x y := y \in drop (index x p) p.

Lemma mem2l p x y : mem2 p x y -> x \in p.
Proof.
by rewrite /mem2 -!index_mem size_drop ltn_subRL; apply/leq_ltn_trans/leq_addr.
Qed.

Lemma mem2lf {p x y} : x \notin p -> mem2 p x y = false.
Proof. exact/contraNF/mem2l. Qed.

Lemma mem2r p x y : mem2 p x y -> y \in p.
Proof.
by rewrite -[in y \in p](cat_take_drop (index x p) p) mem_cat orbC /mem2 => ->.
Qed.

Lemma mem2rf {p x y} : y \notin p -> mem2 p x y = false.
Proof. exact/contraNF/mem2r. Qed.

Lemma mem2_cat p1 p2 x y :
  mem2 (p1 ++ p2) x y = mem2 p1 x y || mem2 p2 x y || (x \in p1) && (y \in p2).
Proof.
rewrite [LHS]/mem2 index_cat fun_if if_arg !drop_cat addKn.
case: ifPn => [p1x | /mem2lf->]; last by rewrite ltnNge leq_addr orbF.
by rewrite index_mem p1x mem_cat -orbA (orb_idl (@mem2r _ _ _)).
Qed.

Lemma mem2_splice p1 p3 x y p2 :
  mem2 (p1 ++ p3) x y -> mem2 (p1 ++ p2 ++ p3) x y.
Proof.
by rewrite !mem2_cat mem_cat andb_orr orbC => /or3P[]->; rewrite ?orbT.
Qed.

Lemma mem2_splice1 p1 p3 x y z :
  mem2 (p1 ++ p3) x y -> mem2 (p1 ++ z :: p3) x y.
Proof. exact: mem2_splice [::z]. Qed.

Lemma mem2_cons x p y z :
  mem2 (x :: p) y z = (if x == y then z \in x :: p else mem2 p y z).
Proof. by rewrite [LHS]/mem2 /=; case: ifP. Qed.

Lemma mem2_seq1 x y z : mem2 [:: x] y z = (y == x) && (z == x).
Proof. by rewrite mem2_cons eq_sym inE. Qed.

Lemma mem2_last y0 p x : mem2 p x (last y0 p) = (x \in p).
Proof.
apply/idP/idP; first exact: mem2l; rewrite -index_mem /mem2 => p_x.
by rewrite -nth_last -(subnKC p_x) -nth_drop mem_nth // size_drop subnSK.
Qed.

Lemma mem2l_cat {p1 p2 x} : x \notin p1 -> mem2 (p1 ++ p2) x =1 mem2 p2 x.
Proof. by move=> p1'x y; rewrite mem2_cat (negPf p1'x) mem2lf ?orbF. Qed.

Lemma mem2r_cat {p1 p2 x y} : y \notin p2 -> mem2 (p1 ++ p2) x y = mem2 p1 x y.
Proof.
by move=> p2'y; rewrite mem2_cat (negPf p2'y) -orbA orbC andbF mem2rf.
Qed.

Lemma mem2lr_splice {p1 p2 p3 x y} :
  x \notin p2 -> y \notin p2 -> mem2 (p1 ++ p2 ++ p3) x y = mem2 (p1 ++ p3) x y.
Proof.
move=> p2'x p2'y; rewrite catA !mem2_cat !mem_cat.
by rewrite (negPf p2'x) (negPf p2'y) (mem2lf p2'x) andbF !orbF.
Qed.

Lemma mem2E s x y :
  mem2 s x y = subseq (if x == y then [:: x] else [:: x; y]) s.
Proof.
elim: s => [| h s]; first by case: ifP.
rewrite mem2_cons => ->.
do 2 rewrite inE (fun_if subseq) !if_arg !sub1seq /=.
by case: eqVneq => [->|]; case: eqVneq.
Qed.

Variant split2r x y : seq T -> Type :=
  Split2r p1 p2 of y \in x :: p2 : split2r x y (p1 ++ x :: p2).

Lemma splitP2r p x y : mem2 p x y -> split2r x y p.
Proof.
move=> pxy; have px := mem2l pxy.
have:= pxy; rewrite /mem2 (drop_nth x) ?index_mem ?nth_index //.
by case/splitP: px => p1 p2; rewrite cat_rcons.
Qed.

Fixpoint shorten x p :=
  if p is y :: p' then
    if x \in p then shorten x p' else y :: shorten y p'
  else [::].

Variant shorten_spec x p : T -> seq T -> Type :=
   ShortenSpec p' of path e x p' & uniq (x :: p') & subpred (mem p') (mem p) :
     shorten_spec x p (last x p') p'.

Lemma shortenP x p : path e x p -> shorten_spec x p (last x p) (shorten x p).
Proof.
move=> e_p; have: x \in x :: p by apply: mem_head.
elim: p x {1 3 5}x e_p => [|y2 p IHp] x y1.
  by rewrite mem_seq1 => _ /eqP->.
rewrite inE orbC /= => /andP[ey12 /IHp {IHp}IHp].
case: ifPn => [y2p_x _ | not_y2p_x /eqP def_x].
  have [p' e_p' Up' p'p] := IHp _ y2p_x.
  by split=> // y /p'p; apply: predU1r.
have [p' e_p' Up' p'p] := IHp y2 (mem_head y2 p).
have{p'p} p'p z: z \in y2 :: p' -> z \in y2 :: p.
  by rewrite !inE; case: (z == y2) => // /p'p.
rewrite -(last_cons y1) def_x; split=> //=; first by rewrite ey12.
by rewrite (contra (p'p y1)) -?def_x.
Qed.

End EqPath.

Section EqHomoPath.

Variables (T : eqType) (T' : Type) (f : T -> T') (leT : rel T) (leT' : rel T').

Lemma homo_path_in x s : {in x :: s &, {homo f : x y / leT x y >-> leT' x y}} ->
  path leT x s -> path leT' (f x) (map f s).
Proof.
move=> f_homo; elim: s => //= y s IHs in x f_homo *; move=> /andP[x_y y_s].
rewrite f_homo ?(in_cons, mem_head, eqxx, orbT) ?IHs//= => z t z_mem t_mem.
by apply: f_homo; rewrite in_cons ?(z_mem, t_mem, orbT).
Qed.

Lemma mono_path_in x s : {in x :: s &, {mono f : x y / leT x y >-> leT' x y}} ->
  path leT' (f x) (map f s) = path leT x s.
Proof.
move=> f_mono; elim: s => //= y s IHs in x f_mono *.
rewrite f_mono ?(in_cons, mem_head, eqxx, orbT) ?IHs//= => z t z_mem t_mem.
by rewrite f_mono// in_cons ?(z_mem, t_mem, orbT).
Qed.

End EqHomoPath.

Arguments homo_path_in {T T' f leT leT' x s}.
Arguments mono_path_in {T T' f leT leT' x s}.

(* Ordered paths and sorting. *)

Section SortSeq.

Variables (T : Type) (leT : rel T).

Fixpoint merge s1 :=
  if s1 is x1 :: s1' then
    let fix merge_s1 s2 :=
      if s2 is x2 :: s2' then
        if leT x1 x2 then x1 :: merge s1' s2 else x2 :: merge_s1 s2'
      else s1 in
    merge_s1
  else id.

Arguments merge !s1 !s2 : rename.

Fixpoint merge_sort_push s1 ss :=
  match ss with
  | [::] :: ss' | [::] as ss' => s1 :: ss'
  | s2 :: ss' => [::] :: merge_sort_push (merge s2 s1) ss'
  end.

Fixpoint merge_sort_pop s1 ss :=
  if ss is s2 :: ss' then merge_sort_pop (merge s2 s1) ss' else s1.

Fixpoint merge_sort_rec ss s :=
  if s is [:: x1, x2 & s'] then
    let s1 := if leT x1 x2 then [:: x1; x2] else [:: x2; x1] in
    merge_sort_rec (merge_sort_push s1 ss) s'
  else merge_sort_pop s ss.

Definition sort := merge_sort_rec [::].

(* The following definition `sort_rec1` is an auxiliary function for          *)
(* inductive reasoning on `sort`. One can rewrite `sort le s` to              *)
(* `sort_rec1 le [::] s` by `sortE` and apply the simple structural induction *)
(* on `s` to reason about it.                                                 *)
Fixpoint sort_rec1 ss s :=
  if s is x :: s then sort_rec1 (merge_sort_push [:: x] ss) s else
  merge_sort_pop [::] ss.

Lemma sortE s : sort s = sort_rec1 [::] s.
Proof.
transitivity (sort_rec1 [:: nil] s); last by case: s.
rewrite /sort; move: [::] {2}_.+1 (ltnSn (size s)./2) => ss n.
by elim: n => // n IHn in ss s *; case: s => [|x [|y s]] //= /IHn->.
Qed.

Definition sorted s := if s is x :: s' then path leT x s' else true.

Lemma path_sorted x s : path leT x s -> sorted s.
Proof. by case: s => //= y s /andP[]. Qed.

Hypothesis leT_total : total leT.

Lemma merge_path x s1 s2 :
  path leT x s1 -> path leT x s2 -> path leT x (merge s1 s2).
Proof.
elim: s1 s2 x => //= x1 s1 IHs1.
elim=> //= x2 s2 IHs2 x /andP[le_x_x1 ord_s1] /andP[le_x_x2 ord_s2].
case: ifP => le_x21 /=; first by rewrite le_x_x1 {}IHs1 //= le_x21.
by rewrite le_x_x2 IHs2 //=; have:= leT_total x1 x2; rewrite le_x21 /= => ->.
Qed.

Lemma merge_sorted s1 s2 : sorted s1 -> sorted s2 -> sorted (merge s1 s2).
Proof.
case: s1 s2 => [|x1 s1] [|x2 s2] //= ord_s1 ord_s2.
case: ifP => le_x21 /=; first by apply: merge_path => //=; rewrite le_x21.
apply: (@merge_path x2 (x1 :: s1)) => //=.
by have:= (leT_total x1 x2); rewrite le_x21 /= => ->.
Qed.

Lemma sort_sorted s : sorted (sort s).
Proof.
rewrite sortE; have: all sorted [::] by [].
elim: s [::] => /= [|x s ihs] ss allss.
- elim: ss [::] (erefl : sorted [::]) allss => //= s ss ihss t ht /andP [hs].
  exact/ihss/merge_sorted.
- apply/ihs; elim: ss [:: x] allss (erefl : sorted [:: x]) => /= [_ _ -> //|].
  by move=> {x s ihs} [|x s] ss ihss t /andP [] hs allss ht;
    [rewrite /= ht | apply/ihss/merge_sorted].
Qed.

Lemma path_min_sorted x s : all (leT x) s -> path leT x s = sorted s.
Proof. by case: s => //= y s /andP [->]. Qed.

Lemma size_merge s1 s2 : size (merge s1 s2) = size (s1 ++ s2).
Proof.
rewrite size_cat; elim: s1 s2 => // x s1 IH1.
elim=> //= [|y s2 IH2]; first by rewrite addn0.
by case: leT; rewrite /= ?IH1 ?IH2 !addnS.
Qed.

Lemma order_path_min x s : transitive leT -> path leT x s -> all (leT x) s.
Proof.
move=> leT_tr; elim: s => //= y [//|z s] ihs /andP[xy yz]; rewrite xy {}ihs//.
by move: yz => /= /andP [/(leT_tr _ _ _ xy) ->].
Qed.

Hypothesis leT_tr : transitive leT.

Lemma sorted_merge s t : sorted (s ++ t) -> merge s t = s ++ t.
Proof.
elim: s => //= x s; case: t; rewrite ?cats0 //= => y t ih hp.
move: (order_path_min leT_tr hp).
by rewrite ih ?(path_sorted hp) // all_cat /= => /and3P [_ -> _].
Qed.

Lemma sorted_sort s : sorted s -> sort s = s.
Proof.
pose catss := foldr (fun x => cat ^~ x) (Nil T).
rewrite -{1 3}[s]/(catss [::] ++ s) sortE; elim: s [::] => /= [|x s ihs] ss.
- elim: ss [::] => //= s ss ihss t; rewrite -catA => h_sorted.
  rewrite -ihss ?sorted_merge //.
  by elim: (catss _) h_sorted => //= ? ? ih /path_sorted.
- move=> h_sorted.
  suff x_ss_E: catss (merge_sort_push [:: x] ss) = catss ([:: x] :: ss)
    by rewrite (catA _ [:: _]) -[catss _ ++ _]/(catss ([:: x] :: ss)) -x_ss_E
               ihs // x_ss_E /= -catA.
  have {h_sorted}: sorted (catss ss ++ [:: x]).
    case: (catss _) h_sorted => //= ? ?.
    by rewrite (catA _ [:: _]) cat_path => /andP [].
  elim: ss [:: x] => {x s ihs} //= -[|x s] ss ihss t h_sorted;
    rewrite /= cats0 // sorted_merge ?ihss ?catA //.
  by elim: (catss ss) h_sorted => //= ? ? ih /path_sorted.
Qed.

Lemma path_mask x m s : path leT x s -> path leT x (mask m s).
Proof.
elim: m s x => [|[] m ih] [|y s] x //=; first by case/andP=> -> /ih.
by case/andP => xy /ih; case: (mask _ _) => //= ? ? /andP [] /(leT_tr xy) ->.
Qed.

Lemma path_filter x a s : path leT x s -> path leT x (filter a s).
Proof. by rewrite filter_mask; exact: path_mask. Qed.

Lemma sorted_mask m s : sorted s -> sorted (mask m s).
Proof.
by elim: m s => [|[] m ih] [|x s] //=; [apply/path_mask | move/path_sorted/ih].
Qed.

Lemma sorted_filter a s : sorted s -> sorted (filter a s).
Proof. rewrite filter_mask; exact: sorted_mask. Qed.

End SortSeq.

Arguments path_sorted {T leT x s}.
Arguments order_path_min {T leT x s}.
Arguments path_min_sorted {T leT x s}.
Arguments merge {T} relT !s1 !s2 : rename.

Section SortMap.
Variables (T T' : Type) (f : T' -> T).

Section Monotonicity.
Variables (leT' : rel T') (leT : rel T).

Lemma homo_sorted : {homo f : x y / leT' x y >-> leT x y} ->
  {homo map f : s / sorted leT' s >-> sorted leT s}.
Proof. by move=> /homo_path f_path [|//= x s]. Qed.

Section Strict.
Hypothesis f_mono : {mono f : x y / leT' x y >-> leT x y}.

Lemma mono_sorted : {mono map f : s / sorted leT' s >-> sorted leT s}.
Proof. by case=> //= x s; rewrite (mono_path f_mono). Qed.

Lemma map_merge : {morph map f : s1 s2 / merge leT' s1 s2 >-> merge leT s1 s2}.
Proof.
elim=> //= x s1 IHs1; elim => [|y s2 IHs2] //=; rewrite f_mono.
by case: leT'; rewrite /= ?IHs1 ?IHs2.
Qed.

Lemma map_sort : {morph map f : s1 / sort leT' s1 >-> sort leT s1}.
Proof.
move=> s; rewrite !sortE -[[::] in RHS]/(map (map f) [::]).
elim: s [::] => /= [|x s ihs] ss; rewrite -/(map f [::]) -/(map f [:: _]);
  first by elim: ss [::] => //= x ss ihss ?; rewrite ihss map_merge.
rewrite ihs -/(map f [:: x]); congr sort_rec1.
by elim: ss [:: x] => {x s ihs} [|[|x s] ss ihss] //= ?; rewrite ihss map_merge.
Qed.

End Strict.
End Monotonicity.

Variable (leT : rel T).
Local Notation leTf := (relpre f leT).

Lemma merge_map s1 s2 : merge leT (map f s1) (map f s2) =
                          map f (merge leTf s1 s2).
Proof. exact/esym/map_merge. Qed.

Lemma sort_map s : sort leT (map f s) = map f (sort leTf s).
Proof. exact/esym/map_sort. Qed.

Lemma sorted_map s : sorted leT (map f s) = sorted leTf s.
Proof. exact: mono_sorted. Qed.

End SortMap.

Arguments homo_sorted {T T' f leT' leT}.
Arguments mono_sorted {T T' f leT' leT}.
Arguments map_merge {T T' f leT' leT}.
Arguments map_sort {T T' f leT' leT}.
Arguments merge_map {T T' f leT}.
Arguments sort_map {T T' f leT}.
Arguments sorted_map {T T' f leT}.

Lemma rev_sorted (T : Type) (leT : rel T) s :
  sorted leT (rev s) = sorted (fun y x => leT x y) s.
Proof. by case: s => //= x p; rewrite -rev_path lastI rev_rcons. Qed.

Section EqSortSeq.

Variable T : eqType.
Variable leT : rel T.

Local Notation merge := (merge leT).
Local Notation sort := (sort leT).
Local Notation sorted := (sorted leT).

Section Transitive.

Hypothesis leT_tr : transitive leT.

Lemma subseq_order_path x s1 s2 :
  subseq s1 s2 -> path leT x s2 -> path leT x s1.
Proof. by case/subseqP => m _ ->; apply/path_mask. Qed.

Lemma subseq_sorted s1 s2 : subseq s1 s2 -> sorted s2 -> sorted s1.
Proof. by case/subseqP => m _ ->; apply/sorted_mask. Qed.

Lemma sorted_uniq : irreflexive leT -> forall s, sorted s -> uniq s.
Proof.
move=> leT_irr; elim=> //= x s IHs s_ord.
rewrite (IHs (path_sorted s_ord)) andbT; apply/negP=> s_x.
by case/allPn: (order_path_min leT_tr s_ord); exists x; rewrite // leT_irr.
Qed.

Lemma eq_sorted : antisymmetric leT ->
  forall s1 s2, sorted s1 -> sorted s2 -> perm_eq s1 s2 -> s1 = s2.
Proof.
move=> leT_asym; elim=> [|x1 s1 IHs1] s2 //= ord_s1 ord_s2 eq_s12.
  by case: {+}s2 (perm_size eq_s12).
have s2_x1: x1 \in s2 by rewrite -(perm_mem eq_s12) mem_head.
case: s2 s2_x1 eq_s12 ord_s2 => //= x2 s2; rewrite in_cons.
case: eqP => [<- _| ne_x12 /= s2_x1] eq_s12 ord_s2.
  by rewrite {IHs1}(IHs1 s2) ?(@path_sorted _ leT x1) // -(perm_cons x1).
case: (ne_x12); apply: leT_asym; rewrite (allP (order_path_min _ ord_s2))//.
have: x2 \in x1 :: s1 by rewrite (perm_mem eq_s12) mem_head.
case/predU1P=> [eq_x12 | s1_x2]; first by case ne_x12.
by rewrite (allP (order_path_min _ ord_s1)).
Qed.

Lemma eq_sorted_irr : irreflexive leT ->
  forall s1 s2, sorted s1 -> sorted s2 -> s1 =i s2 -> s1 = s2.
Proof.
move=> leT_irr s1 s2 s1_sort s2_sort eq_s12.
have: antisymmetric leT.
  by move=> m n /andP[? ltnm]; case/idP: (leT_irr m); apply: leT_tr ltnm.
by move/eq_sorted; apply=> //; apply: uniq_perm => //; apply: sorted_uniq.
Qed.

End Transitive.

Lemma perm_merge s1 s2 : perm_eql (merge s1 s2) (s1 ++ s2).
Proof.
apply/permPl; rewrite perm_sym; elim: s1 s2 => //= x1 s1 IHs1.
elim; rewrite ?cats0 //= => x2 s2 IHs2.
by case: ifP; last rewrite (perm_catCA (_ :: _) [:: x2]); rewrite perm_cons.
Qed.

Lemma mem_merge s1 s2 : merge s1 s2 =i s1 ++ s2.
Proof. by apply: perm_mem; rewrite perm_merge. Qed.

Lemma merge_uniq s1 s2 : uniq (merge s1 s2) = uniq (s1 ++ s2).
Proof. by apply: perm_uniq; rewrite perm_merge. Qed.

Lemma perm_sort s : perm_eql (sort s) s.
Proof.
apply/permPl; rewrite sortE perm_sym -{1}[s]/(flatten [::] ++ s).
elim: s [::] => /= [|x s ihs] ss.
- elim: ss [::] => //= s ss ihss t.
  by rewrite -(permPr (ihss _)) -catA perm_catCA perm_cat2l -perm_merge.
- rewrite -(permPr (ihs _)) (perm_catCA _ [:: x]) catA perm_cat2r.
  elim: ss [:: x] => {x s ihs} // -[|x s] ss ihss t //=.
  rewrite -(permPr (ihss _)) (catA _ (_ :: _)) perm_cat2r perm_catC.
  by rewrite -perm_merge.
Qed.

Lemma mem_sort s : sort s =i s.
Proof. by apply: perm_mem; rewrite perm_sort. Qed.

Lemma sort_uniq s : uniq (sort s) = uniq s.
Proof. by apply: perm_uniq; rewrite perm_sort. Qed.

Lemma perm_sortP :
  total leT -> transitive leT -> antisymmetric leT ->
  forall s1 s2, reflect (sort s1 = sort s2) (perm_eq s1 s2).
Proof.
move=> leT_total leT_tr leT_asym s1 s2.
apply: (iffP idP) => eq12; last by rewrite -perm_sort eq12 perm_sort.
apply: eq_sorted; rewrite ?sort_sorted //.
by rewrite perm_sort (permPl eq12) -perm_sort.
Qed.

End EqSortSeq.

Lemma perm_iota_sort (T : Type) (leT : rel T) x0 s :
  {i_s : seq nat | perm_eq i_s (iota 0 (size s)) &
                   sort leT s = map (nth x0 s) i_s}.
Proof.
exists (sort [rel i j | leT (nth x0 s i) (nth x0 s j)] (iota 0 (size s))).
  by rewrite perm_sort.
by rewrite -[X in sort leT X](mkseq_nth x0) sort_map.
Qed.

Lemma size_sort (T : Type) (leT : rel T) s : size (sort leT s) = size s.
Proof.
case: s => [|x s] //; have [s1 pp qq] := perm_iota_sort leT x (x :: s).
by rewrite qq size_map (perm_size pp) size_iota.
Qed.

Section EqHomoSortSeq.

Variables (T : eqType) (T' : Type) (f : T -> T') (leT : rel T) (leT' : rel T').

Lemma homo_sorted_in s : {in s &, {homo f : x y / leT x y >-> leT' x y}} ->
  sorted leT s -> sorted leT' (map f s).
Proof. by case: s => //= x s /homo_path_in. Qed.

Lemma mono_sorted_in s : {in s &, {mono f : x y / leT x y >-> leT' x y}} ->
  sorted leT' (map f s) = sorted leT s.
Proof. by case: s => // x s /mono_path_in /= ->. Qed.

End EqHomoSortSeq.

Arguments homo_sorted_in {T T' f leT leT'}.
Arguments mono_sorted_in {T T' f leT leT'}.

Lemma ltn_sorted_uniq_leq s : sorted ltn s = uniq s && sorted leq s.
Proof.
case: s => //= n s; elim: s n => //= m s IHs n.
rewrite inE ltn_neqAle negb_or IHs -!andbA.
case sn: (n \in s); last do !bool_congr.
rewrite andbF; apply/and5P=> [[ne_nm lenm _ _ le_ms]]; case/negP: ne_nm.
by rewrite eqn_leq lenm; apply: (allP (order_path_min leq_trans le_ms)).
Qed.

Lemma iota_sorted i n : sorted leq (iota i n).
Proof. by elim: n i => // [[|n] //= IHn] i; rewrite IHn leqW. Qed.

Lemma iota_ltn_sorted i n : sorted ltn (iota i n).
Proof. by rewrite ltn_sorted_uniq_leq iota_sorted iota_uniq. Qed.

Section Stability_merge.

Variables (T : Type) (leT leT' : rel T).
Hypothesis (leT_total : total leT) (leT'_tr : transitive leT').

Let leT_lex := [rel x y | leT x y && (leT y x ==> leT' x y)].

Lemma merge_stable_path x s1 s2 :
  all (fun y => all (leT' y) s2) s1 ->
  path leT_lex x s1 -> path leT_lex x s2 -> path leT_lex x (merge leT s1 s2).
Proof.
elim: s1 s2 x => //= x s1 ih1; elim => //= y s2 ih2 h.
rewrite all_predI -andbA => /and4P [xy' xs2 ys1 s1s2].
case/andP => hx xs1 /andP [] hy ys2; case: ifP => xy /=; rewrite (hx, hy) /=.
- by apply: ih1; rewrite ?all_predI ?ys1 //= xy xy' implybT.
- by apply: ih2; have:= leT_total x y; rewrite ?xs2 //= xy => /= ->.
Qed.

Lemma merge_stable_sorted s1 s2 :
  all (fun x => all (leT' x) s2) s1 ->
  sorted leT_lex s1 -> sorted leT_lex s2 -> sorted leT_lex (merge leT s1 s2).
Proof.
case: s1 s2 => [|x s1] [|y s2] //=; rewrite all_predI -andbA.
case/and4P => [xy' xs2 ys1 s1s2] xs1 ys2; rewrite -/(merge _ (_ :: _)).
by case: ifP (leT_total x y) => /= xy yx; apply/merge_stable_path;
  rewrite /= ?(all_predI, xs2, ys1, xy, yx, xy', implybT).
Qed.

End Stability_merge.

Section Stability.

Variables (T : Type) (leT leT' : rel T).
Variables (leT_total : total leT) (leT_tr : transitive leT).
Variables (leT'_tr : transitive leT').

Local Notation leN x sT := (xrelpre (nth x sT) leT).
Local Notation le_lex x sT :=
  [rel n m | leN x sT n m && (leN x sT m n ==> (n < m))].

Local Arguments iota : simpl never.
Local Arguments size : simpl never.

Let push_invariant := fix push_invariant (ss : seq (seq nat)) :=
  if ss is s :: ss' then
    perm_eq s (iota (size (flatten ss')) (size s)) && push_invariant ss'
  else
    true.

Let push_stable x sT s1 ss :
  all (sorted (le_lex x sT)) (s1 :: ss) -> push_invariant (s1 :: ss) ->
  let ss' := merge_sort_push (leN x sT) s1 ss in
  all (sorted (le_lex x sT)) ss' && push_invariant ss'.
Proof.
elim: ss s1 => [|[|m s2] ss ihss] s1 /=;
  [by rewrite ?andbT => -> | by case/andP => -> -> /andP [->] |].
case/and3P => sorted_s2 sorted_s3 sorted_ss /and3P [perm_s1 perm_s2 perm_ss].
apply: ihss.
- rewrite /= merge_stable_sorted //; apply/allP => y'.
  rewrite (perm_mem perm_s2) mem_iota => /andP [] _ hy'.
  apply/allP => n; rewrite (perm_mem perm_s1) mem_iota => /andP [].
  by rewrite -cat_cons size_cat addnC => /(leq_trans hy').
- rewrite /= perm_ss andbT perm_merge size_merge size_cat iota_add perm_cat //.
  by rewrite addnC -size_cat.
Qed.

Let pop_stable x sT s1 ss :
  all (sorted (le_lex x sT)) (s1 :: ss) -> push_invariant (s1 :: ss) ->
  sorted (le_lex x sT) (merge_sort_pop (leN x sT) s1 ss).
Proof.
elim: ss s1 => [|[|m s2] ss ihss] //= s1; first by rewrite andbT.
case/and3P => sorted_s1 sorted_s2 sorted_ss /and3P [perm_s1 perm_s2 perm_ss].
apply: ihss => /=.
- rewrite sorted_ss andbT; apply: merge_stable_sorted => //.
  apply/allP => m'; rewrite (perm_mem perm_s2) mem_iota => /andP [_ hm'].
  apply/allP => n; rewrite (perm_mem perm_s1) mem_iota -cat_cons size_cat.
  by rewrite addnC => /andP [] /(leq_trans hm').
- rewrite perm_ss andbT perm_merge size_merge size_cat iota_add perm_cat //.
  by rewrite addnC -size_cat.
Qed.

Let sort_iota_stable x sT n : sorted (le_lex x sT) (sort (leN x sT) (iota 0 n)).
Proof.
rewrite sortE (erefl : 0 = size (@flatten nat [::])).
have: push_invariant [::] by [].
have: all (sorted (le_lex x sT)) [::] by [].
elim: n [::] => [|n ihn] ss sorted_ss perm_ss; first exact: pop_stable.
have/(@push_stable x sT): push_invariant ([:: size (flatten ss)] :: ss)
  by rewrite /= perm_refl.
case/(_ sorted_ss)/andP => sorted_push /(ihn _ sorted_push).
congr (sorted _ (sort_rec1 _ _ (iota _ _))).
rewrite -[_.+1]/(size ([:: size (flatten ss)] ++ _)).
elim: (ss) [:: _] => // -[|? ?] ? //= ihss ?.
by rewrite ihss !size_cat size_merge size_cat -addnA addnCA -size_cat.
Qed.

Lemma sort_stable s :
  sorted leT' s ->
  sorted [rel x y | leT x y && (leT y x ==> leT' x y)] (sort leT s).
Proof.
case: {-2}s (erefl s) => // x _ -> sorted_s; rewrite -(mkseq_nth x s) sort_map.
apply/(homo_sorted_in (f := nth x s)): (sort_iota_stable x s (size s)).
move=> /= y z; rewrite !mem_sort !mem_iota !leq0n add0n /= => y_le_s z_le_s.
case/andP => -> /= /implyP yz; apply/implyP => /yz {yz} y_le_z.
elim: s y z sorted_s y_le_z y_le_s z_le_s => // y s ih [|n] [|m] //=;
  rewrite !ltnS -/(size _) => path_s n_m n_s m_s.
- by elim: s y m path_s m_s {ih n_m n_s} =>
    //= z s ih y [|m] /andP [] // y_z z_s m_s; apply/(leT'_tr y_z)/ih.
- exact/ih/m_s/n_s/n_m/path_sorted/path_s.
Qed.

End Stability.

Section Stability_filter.

Variables (T : Type) (leT : rel T).
Variables (leT_total : total leT) (leT_tr : transitive leT).

Local Notation leN x sT := (xrelpre (nth x sT) leT).
Local Notation le_lex x sT :=
  [rel n m | leN x sT n m && (leN x sT m n ==> (n < m))].

Let le_lex_transitive x sT : transitive (le_lex x sT).
Proof.
move=> ? ? ? /andP [xy /implyP xy'] /andP [yz /implyP yz'].
rewrite /= (leT_tr xy yz) /=; apply/implyP => zx.
by apply/ltn_trans: (xy' (leT_tr yz zx)) (yz' (leT_tr zx xy)).
Qed.

Lemma filter_sort p s : filter p (sort leT s) = sort leT (filter p s).
Proof.
case: {-2}s (erefl s) => // x _ ->.
rewrite -(mkseq_nth x s) !(filter_map, sort_map).
congr map; apply/(@eq_sorted_irr _ (le_lex x s)) => //.
- by move=> ?; rewrite /= ltnn implybF andbN.
- exact/sorted_filter/sort_stable/iota_ltn_sorted/ltn_trans.
- exact/sort_stable/sorted_filter/iota_ltn_sorted/ltn_trans/ltn_trans.
- by move=> ?; rewrite !mem_filter !mem_sort mem_filter.
Qed.

End Stability_filter.

Section Stability_mask.

Variables (T : Type) (leT : rel T).
Variables (leT_total : total leT) (leT_tr : transitive leT).

Lemma mask_sort s m :
  {m_s : bitseq | mask m_s (sort leT s) = sort leT (mask m s)}.
Proof.
case: {-2}s (erefl s) => [|x _ ->]; first by case: m; exists [::].
rewrite -(mkseq_nth x s) -map_mask !sort_map.
exists [seq i \in mask m (iota 0 (size s)) |
            i <- sort (xrelpre (nth x s) leT) (iota 0 (size s))].
rewrite -map_mask -filter_mask {2}mask_filter ?iota_uniq ?filter_sort //.
move=> ? ? ?; exact/leT_tr.
Qed.

Lemma sorted_mask_sort s m :
  sorted leT (mask m s) -> {m_s | mask m_s (sort leT s) = mask m s}.
Proof. by move/(sorted_sort leT_tr) => <-; exact: mask_sort. Qed.

End Stability_mask.

Section Stability_subseq.

Variables (T : eqType) (leT : rel T).
Variables (leT_total : total leT) (leT_tr : transitive leT).

Lemma subseq_sort : {homo sort leT : t s / subseq t s}.
Proof.
move=> t s /subseqP [m _ ->].
case: (mask_sort leT_total leT_tr s m) => m' <-; exact: mask_subseq.
Qed.

Lemma sorted_subseq_sort t s :
  subseq t s -> sorted leT t -> subseq t (sort leT s).
Proof. by move=> subseq_ts /(sorted_sort leT_tr) <-; exact: subseq_sort. Qed.

Lemma mem2_sort s x y : leT x y -> mem2 s x y -> mem2 (sort leT s) x y.
Proof.
move=> lexy; rewrite !mem2E => /subseq_sort.
by case: eqP => // _; rewrite {1}/sort /= lexy /=.
Qed.

End Stability_subseq.

(* Function trajectories. *)

Notation fpath f := (path (coerced_frel f)).
Notation fcycle f := (cycle (coerced_frel f)).
Notation ufcycle f := (ucycle (coerced_frel f)).

Prenex Implicits path next prev cycle ucycle mem2.

Section Trajectory.

Variables (T : Type) (f : T -> T).

Fixpoint traject x n := if n is n'.+1 then x :: traject (f x) n' else [::].

Lemma trajectS x n : traject x n.+1 = x :: traject (f x) n.
Proof. by []. Qed.

Lemma trajectSr x n : traject x n.+1 = rcons (traject x n) (iter n f x).
Proof. by elim: n x => //= n IHn x; rewrite IHn -iterSr. Qed.

Lemma last_traject x n : last x (traject (f x) n) = iter n f x.
Proof. by case: n => // n; rewrite iterSr trajectSr last_rcons. Qed.

Lemma traject_iteri x n :
  traject x n = iteri n (fun i => rcons^~ (iter i f x)) [::].
Proof. by elim: n => //= n <-; rewrite -trajectSr. Qed.

Lemma size_traject x n : size (traject x n) = n.
Proof. by elim: n x => //= n IHn x //=; rewrite IHn. Qed.

Lemma nth_traject i n : i < n -> forall x, nth x (traject x n) i = iter i f x.
Proof.
elim: n => // n IHn; rewrite ltnS => le_i_n x.
rewrite trajectSr nth_rcons size_traject.
by case: ltngtP le_i_n => [? _||->] //; apply: IHn.
Qed.

End Trajectory.

Section EqTrajectory.

Variables (T : eqType) (f : T -> T).

Lemma eq_fpath f' : f =1 f' -> fpath f =2 fpath f'.
Proof. by move/eq_frel/eq_path. Qed.

Lemma eq_fcycle f' : f =1 f' -> fcycle f =1 fcycle f'.
Proof. by move/eq_frel/eq_cycle. Qed.

Lemma fpathP x p : reflect (exists n, p = traject f (f x) n) (fpath f x p).
Proof.
elim: p x => [|y p IHp] x; first by left; exists 0.
rewrite /= andbC; case: IHp => [fn_p | not_fn_p]; last first.
  by right=> [] [[//|n]] [<- fn_p]; case: not_fn_p; exists n.
apply: (iffP eqP) => [-> | [[] // _ []//]].
by have [n ->] := fn_p; exists n.+1.
Qed.

Lemma fpath_traject x n : fpath f x (traject f (f x) n).
Proof. by apply/(fpathP x); exists n. Qed.

Definition looping x n := iter n f x \in traject f x n.

Lemma loopingP x n :
  reflect (forall m, iter m f x \in traject f x n) (looping x n).
Proof.
apply: (iffP idP) => loop_n; last exact: loop_n.
case: n => // n in loop_n *; elim=> [|m /= IHm]; first exact: mem_head.
move: (fpath_traject x n) loop_n; rewrite /looping !iterS -last_traject /=.
move: (iter m f x) IHm => y /splitPl[p1 p2 def_y].
rewrite cat_path last_cat def_y; case: p2 => // z p2 /and3P[_ /eqP-> _] _.
by rewrite inE mem_cat mem_head !orbT.
Qed.

Lemma trajectP x n y :
  reflect (exists2 i, i < n & y = iter i f x) (y \in traject f x n).
Proof.
elim: n x => [|n IHn] x /=; first by right; case.
rewrite inE; have [-> | /= neq_xy] := eqP; first by left; exists 0.
apply: {IHn}(iffP (IHn _)) => [[i] | [[|i]]] // lt_i_n ->.
  by exists i.+1; rewrite ?iterSr.
by exists i; rewrite ?iterSr.
Qed.

Lemma looping_uniq x n : uniq (traject f x n.+1) = ~~ looping x n.
Proof.
rewrite /looping; elim: n x => [|n IHn] x //.
rewrite {-3}[n.+1]lock /= -lock {}IHn -iterSr -negb_or inE; congr (~~ _).
apply: orb_id2r => /trajectP no_loop.
apply/idP/eqP => [/trajectP[m le_m_n def_x] | {1}<-]; last first.
  by rewrite iterSr -last_traject mem_last.
have loop_m: looping x m.+1 by rewrite /looping iterSr -def_x mem_head.
have/trajectP[[|i] // le_i_m def_fn1x] := loopingP _ _ loop_m n.+1.
by case: no_loop; exists i; rewrite -?iterSr // -ltnS (leq_trans le_i_m).
Qed.

End EqTrajectory.

Arguments fpathP {T f x p}.
Arguments loopingP {T f x n}.
Arguments trajectP {T f x n y}.
Prenex Implicits traject.

Section UniqCycle.

Variables (n0 : nat) (T : eqType) (e : rel T) (p : seq T).

Hypothesis Up : uniq p.

Lemma prev_next : cancel (next p) (prev p).
Proof.
move=> x; rewrite prev_nth mem_next next_nth; case p_x: (x \in p) => //.
case def_p: p Up p_x => // [y q]; rewrite -{-1}def_p => /= /andP[not_qy Uq] p_x.
rewrite -{2}(nth_index y p_x); congr (nth y _ _); set i := index x p.
have: i <= size q by rewrite -index_mem -/i def_p in p_x.
case: ltngtP => // [lt_i_q|->] _; first by rewrite index_uniq.
by apply/eqP; rewrite nth_default // eqn_leq index_size leqNgt index_mem.
Qed.

Lemma next_prev : cancel (prev p) (next p).
Proof.
move=> x; rewrite next_nth mem_prev prev_nth; case p_x: (x \in p) => //.
case def_p: p p_x => // [y q]; rewrite -def_p => p_x.
rewrite index_uniq //; last by rewrite def_p ltnS index_size.
case q_x: (x \in q); first exact: nth_index.
rewrite nth_default; last by rewrite leqNgt index_mem q_x.
by apply/eqP; rewrite def_p inE q_x orbF eq_sym in p_x.
Qed.

Lemma cycle_next : fcycle (next p) p.
Proof.
case def_p: {-2}p Up => [|x q] Uq //.
apply/(pathP x)=> i; rewrite size_rcons => le_i_q.
rewrite -cats1 -cat_cons nth_cat le_i_q /= next_nth {}def_p mem_nth //.
rewrite index_uniq // nth_cat /= ltn_neqAle andbC -ltnS le_i_q.
by case: (i =P _) => //= ->; rewrite subnn nth_default.
Qed.

Lemma cycle_prev : cycle (fun x y => x == prev p y) p.
Proof.
apply: etrans cycle_next; symmetry; case def_p: p => [|x q] //.
by apply: eq_path; rewrite -def_p; apply: (can2_eq prev_next next_prev).
Qed.

Lemma cycle_from_next : (forall x, x \in p -> e x (next p x)) -> cycle e p.
Proof.
case: p (next p) cycle_next => //= [x q] n; rewrite -(belast_rcons x q x).
move: {q}(rcons q x) => q n_q; move/allP.
by elim: q x n_q => //= _ q IHq x /andP[/eqP <- n_q] /andP[-> /IHq->].
Qed.

Lemma cycle_from_prev : (forall x, x \in p -> e (prev p x) x) -> cycle e p.
Proof.
move=> e_p; apply: cycle_from_next => x p_x.
by rewrite -{1}[x]prev_next e_p ?mem_next.
Qed.

Lemma next_rot : next (rot n0 p) =1 next p.
Proof.
move=> x; have n_p := cycle_next; rewrite -(rot_cycle n0) in n_p.
case p_x: (x \in p); last by rewrite !next_nth mem_rot p_x.
by rewrite (eqP (next_cycle n_p _)) ?mem_rot.
Qed.

Lemma prev_rot : prev (rot n0 p) =1 prev p.
Proof.
move=> x; have p_p := cycle_prev; rewrite -(rot_cycle n0) in p_p.
case p_x: (x \in p); last by rewrite !prev_nth mem_rot p_x.
by rewrite (eqP (prev_cycle p_p _)) ?mem_rot.
Qed.

End UniqCycle.

Section UniqRotrCycle.

Variables (n0 : nat) (T : eqType) (p : seq T).

Hypothesis Up : uniq p.

Lemma next_rotr : next (rotr n0 p) =1 next p. Proof. exact: next_rot. Qed.

Lemma prev_rotr : prev (rotr n0 p) =1 prev p. Proof. exact: prev_rot. Qed.

End UniqRotrCycle.

Section UniqCycleRev.

Variable T : eqType.
Implicit Type p : seq T.

Lemma prev_rev p : uniq p -> prev (rev p) =1 next p.
Proof.
move=> Up x; case p_x: (x \in p); last first.
  by rewrite next_nth prev_nth mem_rev p_x.
case/rot_to: p_x (Up) => [i q def_p] Urp; rewrite -rev_uniq in Urp.
rewrite -(prev_rotr i Urp); do 2 rewrite -(prev_rotr 1) ?rotr_uniq //.
rewrite -rev_rot -(next_rot i Up) {i p Up Urp}def_p.
by case: q => // y q; rewrite !rev_cons !(=^~ rcons_cons, rotr1_rcons) /= eqxx.
Qed.

Lemma next_rev p : uniq p -> next (rev p) =1 prev p.
Proof. by move=> Up x; rewrite -{2}[p]revK prev_rev // rev_uniq. Qed.

End UniqCycleRev.

Section MapPath.

Variables (T T' : Type) (h : T' -> T) (e : rel T) (e' : rel T').

Definition rel_base (b : pred T) :=
  forall x' y', ~~ b (h x') -> e (h x') (h y') = e' x' y'.

Lemma map_path b x' p' (Bb : rel_base b) :
    ~~ has (preim h b) (belast x' p') ->
  path e (h x') (map h p') = path e' x' p'.
Proof. by elim: p' x' => [|y' p' IHp'] x' //= /norP[/Bb-> /IHp'->]. Qed.

End MapPath.

Section MapEqPath.

Variables (T T' : eqType) (h : T' -> T) (e : rel T) (e' : rel T').

Hypothesis Ih : injective h.

Lemma mem2_map x' y' p' : mem2 (map h p') (h x') (h y') = mem2 p' x' y'.
Proof. by rewrite {1}/mem2 (index_map Ih) -map_drop mem_map. Qed.

Lemma next_map p : uniq p -> forall x, next (map h p) (h x) = h (next p x).
Proof.
move=> Up x; case p_x: (x \in p); last by rewrite !next_nth (mem_map Ih) p_x.
case/rot_to: p_x => i p' def_p.
rewrite -(next_rot i Up); rewrite -(map_inj_uniq Ih) in Up.
rewrite -(next_rot i Up) -map_rot {i p Up}def_p /=.
by case: p' => [|y p''] //=; rewrite !eqxx.
Qed.

Lemma prev_map p : uniq p -> forall x, prev (map h p) (h x) = h (prev p x).
Proof.
move=> Up x; rewrite -{1}[x](next_prev Up) -(next_map Up).
by rewrite prev_next ?map_inj_uniq.
Qed.

End MapEqPath.

Definition fun_base (T T' : eqType) (h : T' -> T) f f' :=
  rel_base h (frel f) (frel f').

Section CycleArc.

Variable T : eqType.
Implicit Type p : seq T.

Definition arc p x y := let px := rot (index x p) p in take (index y px) px.

Lemma arc_rot i p : uniq p -> {in p, arc (rot i p) =2 arc p}.
Proof.
move=> Up x p_x y; congr (fun q => take (index y q) q); move: Up p_x {y}.
rewrite -{1 2 5 6}(cat_take_drop i p) /rot cat_uniq => /and3P[_ Up12 _].
rewrite !drop_cat !take_cat !index_cat mem_cat orbC.
case p2x: (x \in drop i p) => /= => [_ | p1x].
  rewrite index_mem p2x [x \in _](negbTE (hasPn Up12 _ p2x)) /= addKn.
  by rewrite ltnNge leq_addr catA.
by rewrite p1x index_mem p1x addKn ltnNge leq_addr /= catA.
Qed.

Lemma left_arc x y p1 p2 (p := x :: p1 ++ y :: p2) :
  uniq p -> arc p x y = x :: p1.
Proof.
rewrite /arc /p [index x _]/= eqxx rot0 -cat_cons cat_uniq index_cat.
move: (x :: p1) => xp1 /and3P[_ /norP[/= /negbTE-> _] _].
by rewrite eqxx addn0 take_size_cat.
Qed.

Lemma right_arc x y p1 p2 (p := x :: p1 ++ y :: p2) :
  uniq p -> arc p y x = y :: p2.
Proof.
rewrite -[p]cat_cons -rot_size_cat rot_uniq => Up.
by rewrite arc_rot ?left_arc ?mem_head.
Qed.

Variant rot_to_arc_spec p x y :=
    RotToArcSpec i p1 p2 of x :: p1 = arc p x y
                          & y :: p2 = arc p y x
                          & rot i p = x :: p1 ++ y :: p2 :
    rot_to_arc_spec p x y.

Lemma rot_to_arc p x y :
  uniq p -> x \in p -> y \in p -> x != y -> rot_to_arc_spec p x y.
Proof.
move=> Up p_x p_y ne_xy; case: (rot_to p_x) (p_y) (Up) => [i q def_p] q_y.
rewrite -(mem_rot i) def_p inE eq_sym (negbTE ne_xy) in q_y.
rewrite -(rot_uniq i) def_p.
case/splitPr: q / q_y def_p => q1 q2 def_p Uq12; exists i q1 q2 => //.
  by rewrite -(arc_rot i Up p_x) def_p left_arc.
by rewrite -(arc_rot i Up p_y) def_p right_arc.
Qed.

End CycleArc.

Prenex Implicits arc.

Section Monotonicity.

Variables (T : eqType) (r : rel T).

Hypothesis r_trans : transitive r.

Lemma sorted_lt_nth x0 (s : seq T) : sorted r s ->
  {in [pred n | n < size s] &, {homo nth x0 s : i j / i < j >-> r i j}}.
Proof.
move=> s_sorted i j; rewrite -!topredE /=.
wlog ->: i j s s_sorted / i = 0 => [/(_ 0 (j - i) (drop i s)) hw|] ilt jlt ltij.
  move: hw; rewrite !size_drop !nth_drop addn0 subnKC ?(ltnW ltij) //.
  by rewrite (subseq_sorted _ (drop_subseq _ _)) ?subn_gt0 ?ltn_sub2r//; apply.
case: s ilt j jlt ltij => [|x s] //= _ [//|j] jlt _ in s_sorted *.
by have /allP -> //= := order_path_min r_trans s_sorted; rewrite mem_nth.
Qed.

Lemma ltn_index (s : seq T) : sorted r s ->
  {in s &, forall x y, index x s < index y s -> r x y}.
Proof.
case: s => [//|x0 s'] r_sorted x y xs ys.
move=> /(@sorted_lt_nth x0 (x0 :: s')).
by rewrite ?nth_index ?[_ \in gtn _]index_mem //; apply.
Qed.

Hypothesis r_refl : reflexive r.

Lemma sorted_le_nth x0 (s : seq T) : sorted r s ->
  {in [pred n | n < size s] &, {homo nth x0 s : i j / i <= j >-> r i j}}.
Proof.
move=> s_sorted x y xs ys.
by rewrite leq_eqVlt=> /orP[/eqP->//|/sorted_lt_nth]; apply.
Qed.

Lemma leq_index (s : seq T) : sorted r s ->
  {in s &, forall x y, index x s <= index y s -> r x y}.
Proof.
case: s => [//|x0 s'] r_sorted x y xs ys.
move=> /(@sorted_le_nth x0 (x0 :: s')).
by rewrite ?nth_index ?[_ \in gtn _]index_mem //; apply.
Qed.

End Monotonicity.
