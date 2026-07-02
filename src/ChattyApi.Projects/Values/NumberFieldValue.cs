using System.Text.Json;

namespace ChattyApi.Projects.Values;

/// <summary>
/// A numeric value, serialized as a raw JSON number (e.g. <c>42</c>, never <c>"42"</c>).
/// Backed by <see cref="decimal"/> to preserve exact decimal digits (no binary floating-point drift).
/// </summary>
public sealed class NumberFieldValue : FieldValue
{
    /// <summary>The shared null (unset) number value.</summary>
    public static NumberFieldValue Null { get; } = new(null);

    public NumberFieldValue(decimal? value)
    {
        Value = value;
    }

    public decimal? Value { get; }

    public override FieldType Type => FieldType.Number;

    public override bool HasValue => Value.HasValue;

    internal static NumberFieldValue ReadJson(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Number)
        {
            throw new JsonException(
                $"a 'number' field value must be a raw JSON number but was '{value.ValueKind}'.");
        }

        if (!value.TryGetDecimal(out decimal number))
        {
            throw new JsonException(
                $"the number '{value.GetRawText()}' is outside the range supported for 'number' fields (System.Decimal).");
        }

        return new NumberFieldValue(number);
    }

    internal override void WriteJson(Utf8JsonWriter writer)
    {
        if (Value is null)
        {
            writer.WriteNullValue();
        }
        else
        {
            writer.WriteNumberValue(Value.Value);
        }
    }
}
