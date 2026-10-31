import Lean.Data.Json
-- Strict JSON parsing for registry files.
-- Why not Lean.Json.parse: the standard parser SILENTLY COLLAPSES duplicate object keys
-- (last wins). In an ID-keyed registry that is a shadowing channel: a hand-edited or
-- generated file could carry two "A1" entries and the checker would see only one.
-- This parser rejects duplicate keys at any depth, rejects trailing garbage, and is the
-- ONLY way registry files enter the checker.
namespace Dagcheck

open Lean (Json JsonNumber)

private def ws : List Char → List Char
  | c :: rest => if c == ' ' || c == '\t' || c == '\n' || c == '\r' then ws rest else c :: rest
  | [] => []

private def hexVal (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c && c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c && c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

private partial def pStringChars : List Char → Except String (String × List Char)
  | [] => .error "unterminated string"
  | '"' :: rest => .ok ("", rest)
  | '\\' :: e :: rest =>
    let esc : Except String Char := match e with
      | '"' => .ok '"'
      | '\\' => .ok '\\'
      | '/' => .ok '/'
      | 'n' => .ok '\n'
      | 't' => .ok '\t'
      | 'r' => .ok '\r'
      | 'b' => .ok (Char.ofNat 8)
      | 'f' => .ok (Char.ofNat 12)
      | 'u' => .error "unicode-escape sentinel"  -- handled below
      | _ => .error s!"bad escape \\{e}"
    match e with
    | 'u' =>
      match rest with
      | h1 :: h2 :: h3 :: h4 :: rest' =>
        match hexVal h1, hexVal h2, hexVal h3, hexVal h4 with
        | some a, some b, some c, some d =>
          let n := a * 4096 + b * 256 + c * 16 + d
          if 0xD800 ≤ n && n ≤ 0xDFFF then .error "surrogate-pair \\u escapes unsupported (use literal UTF-8)"
          else match pStringChars rest' with
            | .ok (s, r) => .ok (String.singleton (Char.ofNat n) ++ s, r)
            | .error e' => .error e'
        | _, _, _, _ => .error "bad \\uXXXX escape"
      | _ => .error "truncated \\u escape"
    | _ =>
      match esc with
      | .error e' => .error e'
      | .ok ch =>
        match pStringChars rest with
        | .ok (s, r) => .ok (String.singleton ch ++ s, r)
        | .error e' => .error e'
  | c :: rest =>
    match pStringChars rest with
    | .ok (s, r) => .ok (String.singleton c ++ s, r)
    | .error e => .error e

private def takeDigits : List Char → String × List Char
  | c :: rest =>
    if c.isDigit then
      let (s, r) := takeDigits rest
      (String.singleton c ++ s, r)
    else ("", c :: rest)
  | [] => ("", [])

private def pow10 : Nat → Nat
  | 0 => 1
  | n + 1 => 10 * pow10 n

/-- Parse a JSON number starting at a digit or '-'. -/
private def pNumber (chars : List Char) : Except String (Json × List Char) :=
  let (neg, rest1) := match chars with
    | '-' :: rest => (true, rest)
    | _ => (false, chars)
  let (intPart, rest2) := takeDigits rest1
  if intPart.isEmpty then .error "expected number"
  else
    match rest2 with
    | '.' :: rest =>
      let (f, r) := takeDigits rest
      if f.isEmpty then .error "digits required after '.'"
      else
        finishNum neg intPart f r
    | _ => finishNum neg intPart "" rest2
where
  finishNum (neg : Bool) (intPart fracPart : String) (rest : List Char) : Except String (Json × List Char) :=
    let (expNeg, expPart, rest') := match rest with
      | e :: rest0 =>
        if e == 'e' || e == 'E' then
          match rest0 with
          | sgn :: rest1 =>
            if sgn == '+' then
              let (ds, r) := takeDigits rest1
              (false, ds, r)
            else if sgn == '-' then
              let (ds, r) := takeDigits rest1
              (true, ds, r)
            else
              let (ds, r) := takeDigits (sgn :: rest1)
              (false, ds, r)
          | [] => (false, "", [])
        else (false, "", rest)
      | [] => (false, "", [])
    -- adversarial bounds: parser work must stay linear in sane input. Exponents beyond
    -- two digits or mantissas beyond 40 digits are rejected, never exponentiated.
    if expPart.length > 2 then
      .error s!"number exponent out of supported range (|exp| <= 99)"
    else if intPart.length > 40 || fracPart.length > 40 then
      .error "number has too many digits (>40 unsupported)"
    else
    let digits := intPart ++ fracPart
    let mant := digits.toInt!
    let mant := if neg then -mant else mant
    let fracLen := fracPart.length
    if expPart.isEmpty && (match rest with | e :: _ => e == 'e' || e == 'E' | [] => false) then
      .error "digits required in exponent"
    else
      let e := if expPart.isEmpty then 0 else expPart.toNat!
      let e := if expNeg then - (e : Int) else (e : Int)
      let k : Int := (e : Int) - fracLen
      let num : JsonNumber :=
        if k ≥ 0 then ⟨mant * (pow10 k.toNat : Nat), 0⟩
        else ⟨mant, (-k).toNat⟩
      .ok (Json.num num, rest')

/-- Maximum accepted JSON nesting depth. Registry JSON legitimately nests about 10
    levels; 500 is generous headroom. Deeper input is a resource attack (the D6 class),
    not data, and is rejected before any semantic work happens. -/
def maxJsonDepth : Nat := 500

mutual
private partial def pValue : Nat → Nat → List Char → Except String (Json × List Char)
  | 0, _, _ => .error "parser fuel exhausted (internal limit; report as bug)"
  | fuel + 1, depth, chars =>
    if depth > maxJsonDepth then
      .error s!"JSON nesting deeper than {maxJsonDepth} levels (resource bound)"
    else match ws chars with
    | '{' :: rest => pObject fuel (depth + 1) rest
    | '[' :: rest => pArray fuel (depth + 1) rest
    | '"' :: rest =>
      match pStringChars rest with
      | .ok (s, r) => .ok (Json.str s, r)
      | .error e => .error e
    | 't' :: 'r' :: 'u' :: 'e' :: rest => .ok (Json.bool true, rest)
    | 'f' :: 'a' :: 'l' :: 's' :: 'e' :: rest => .ok (Json.bool false, rest)
    | 'n' :: 'u' :: 'l' :: 'l' :: rest => .ok (Json.null, rest)
    | c :: _ => if c.isDigit || c == '-' then pNumber (ws chars) else .error s!"unexpected character '{c}'"
    | [] => .error "unexpected end of input"

private partial def pObject : Nat → Nat → List Char → Except String (Json × List Char)
  | 0, _, _ => .error "parser fuel exhausted (internal limit; report as bug)"
  | fuel + 1, depth, chars =>
    match ws chars with
    | '}' :: rest => .ok (Json.mkObj [], rest)
    | chars' => pPairs fuel depth chars' []
where
  pPairs : Nat → Nat → List Char → List (String × Json) → Except String (Json × List Char)
    | 0, _, _, _ => .error "parser fuel exhausted (internal limit; report as bug)"
    | fuel + 1, depth, chars, acc =>
      match ws chars with
      | '"' :: rest =>
        match pStringChars rest with
        | .error e => .error e
        | .ok (k, rest1) =>
          match ws rest1 with
          | ':' :: rest2 =>
            match pValue fuel depth (ws rest2) with
            | .error e => .error e
            | .ok (v, rest3) =>
              if acc.any (fun p => p.1 == k) then
                .error s!"duplicate key \"{k}\" in object"
              else
                match ws rest3 with
                | ',' :: rest4 => pPairs fuel depth rest4 (acc ++ [(k, v)])
                | '}' :: rest4 => .ok (Json.mkObj (acc ++ [(k, v)]), rest4)
                | _ => .error "expected ',' or '}' in object"
          | _ => .error "expected ':' after object key"
      | _ => .error "expected string key in object"

private partial def pArray : Nat → Nat → List Char → Except String (Json × List Char)
  | 0, _, _ => .error "parser fuel exhausted (internal limit; report as bug)"
  | fuel + 1, depth, chars =>
    match ws chars with
    | ']' :: rest => .ok (Json.arr #[], rest)
    | chars' => pElems fuel depth chars' #[]
where
  pElems : Nat → Nat → List Char → Array Json → Except String (Json × List Char)
    | 0, _, _, _ => .error "parser fuel exhausted (internal limit; report as bug)"
    | fuel + 1, depth, chars, acc =>
      match pValue fuel depth (ws chars) with
      | .error e => .error e
      | .ok (v, rest1) =>
        match ws rest1 with
        | ',' :: rest2 => pElems fuel depth rest2 (acc.push v)
        | ']' :: rest2 => .ok (Json.arr (acc.push v), rest2)
        | _ => .error "expected ',' or ']' in array"
end

/-- Parse a complete JSON text strictly: duplicate keys rejected, trailing garbage rejected. -/
def parseJsonStrict (s : String) : Except String Json :=
  let chars := s.toList
  match pValue (chars.length + 1) 1 chars with
  | .error e => .error e
  | .ok (j, rest) =>
    if (ws rest).isEmpty then .ok j
    else .error "trailing content after JSON value"

end Dagcheck
