import Dagcheck.Consist
-- Axiom audit for the verified core. Expected, and asserted by the test suite:
--   soundness theorems: [propext, Quot.sound] (standard Lean axioms only)
--   consistency theorems: no native computation, no sorry
namespace Dagcheck
#print axioms applyRule_sound
#print axioms checkDeriv_sound
#print axioms consistent_sound
#print axioms consistent_complete
end Dagcheck
