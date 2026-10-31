-- Date arithmetic for the registry-spec staleness policy. Pure and total; tested against
-- known epoch values in Dagcheck.Tests.
namespace Dagcheck

structure Date where
  y : Int
  m : Int
  d : Int
  deriving Repr, DecidableEq

def isLeap (y : Int) : Bool := y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)

def daysInMonth (y m : Int) : Int :=
  if m == 2 then (if isLeap y then 29 else 28)
  else if m == 4 || m == 6 || m == 9 || m == 11 then 30
  else 31

def isValidDate (y m d : Int) : Bool :=
  1 ≤ m && m ≤ 12 && 1 ≤ d && d ≤ daysInMonth y m

/-- Days from civil epoch (Howard Hinnant's algorithm). 1970-01-01 = 0. -/
def daysFromCivil (y m d : Int) : Int :=
  let y' := if m ≤ 2 then y - 1 else y
  let era := y' / 400
  let yoe := y' - era * 400
  let mp := (5 * (if m > 2 then m - 3 else m + 9) + 2) / 5
  let doy := (153 * mp + 2) / 5 + d - 1
  let doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468

/-- Strict YYYY-MM-DD parsing (4-2-2 digit shapes, real calendar dates only). -/
def parseDate (s : String) : Option Date :=
  match s.splitOn "-" with
  | [ys, ms, ds] =>
    match ys.toInt?, ms.toInt?, ds.toInt? with
    | some y, some m, some d =>
      if ys.length == 4 && ms.length == 2 && ds.length == 2 && isValidDate y m d
      then some ⟨y, m, d⟩ else none
    | _, _, _ => none
  | _ => none

/-- Staleness per registry-spec: today STRICTLY AFTER lastActivity + period. -/
def staleBy (today lastActivity : Date) (periodDays : Nat) : Bool :=
  daysFromCivil today.y today.m today.d > daysFromCivil lastActivity.y lastActivity.m lastActivity.d + periodDays

end Dagcheck
