import Dagcheck
open Dagcheck
-- Axiom audit: the kernel lists every axiom each soundness theorem depends on.
-- Expected: propext and Quot.sound only (Lean's standard classical axioms).
-- Any native axiom (sorry, native_decide trust) would appear here and FAIL review.
#print axioms applyRule_sound
#print axioms checkDeriv_sound
#print axioms consistent_sound
#print axioms consistent_complete
