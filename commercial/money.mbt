///|
let int64_max : Int64 = 9223372036854775807L

///|
let int64_min : Int64 = -9223372036854775807L - 1L

///|
fn valid_currency(currency : String) -> Bool {
  currency.length() == 3 &&
  currency.all(character => character >= 'A' && character <= 'Z')
}

///|
pub fn money(
  minor_units : Int64,
  currency : String,
  scale : Int,
) -> FixedMoney raise CommercialError {
  if !valid_currency(currency) || scale < 0 || scale > 9 {
    raise InvalidInput(
      "money requires an uppercase ISO currency and scale 0..9",
    )
  }
  { minor_units, currency, scale }
}

///|
fn ensure_same_money_unit(
  left : FixedMoney,
  right : FixedMoney,
) -> Unit raise CommercialError {
  if left.currency != right.currency || left.scale != right.scale {
    raise CurrencyMismatch
  }
}

///|
fn checked_add_int64(
  left : Int64,
  right : Int64,
) -> Int64 raise CommercialError {
  if (right > 0L && left > int64_max - right) ||
    (right < 0L && left < int64_min - right) {
    raise ArithmeticOverflow
  }
  left + right
}

///|
fn checked_multiply_nonnegative(
  left : Int64,
  right : Int64,
) -> Int64 raise CommercialError {
  if left < 0L || right < 0L {
    raise InvalidInput("rated quantity and unit price must be non-negative")
  }
  if right != 0L && left > int64_max / right {
    raise ArithmeticOverflow
  }
  left * right
}

///|
pub fn FixedMoney::add(
  self : FixedMoney,
  other : FixedMoney,
) -> FixedMoney raise CommercialError {
  ensure_same_money_unit(self, other)
  {
    ..self,
    minor_units: checked_add_int64(self.minor_units, other.minor_units),
  }
}

///|
pub fn FixedMoney::negate(
  self : FixedMoney,
) -> FixedMoney raise CommercialError {
  if self.minor_units == int64_min {
    raise ArithmeticOverflow
  }
  { ..self, minor_units: -self.minor_units }
}

///|
fn rated_amount(
  quantity : Int64,
  price : FixedMoney,
) -> FixedMoney raise CommercialError {
  {
    ..price,
    minor_units: checked_multiply_nonnegative(quantity, price.minor_units),
  }
}

///| Compute a bounded estimate using the same exact fixed-point arithmetic as

///|
/// ledger rating. This is used by admission before a lease is committed.
pub fn estimate_cost(
  quantity : Int64,
  unit_price : FixedMoney,
) -> FixedMoney raise CommercialError {
  rated_amount(quantity, unit_price)
}

///|
fn zero_like(value : FixedMoney) -> FixedMoney {
  { ..value, minor_units: 0L }
}
