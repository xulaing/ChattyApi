using System.Text.Json;

namespace ChattyApi.Projects.Values;

/// <summary>
/// A date value. JSON has no native date type, so dates are serialized as ISO 8601
/// strings (e.g. <c>"2026-07-02T00:00:00+00:00"</c>) — the interoperable, culture-invariant
/// convention — and are strictly validated on read: an arbitrary string that is not a
/// valid ISO 8601 date/time is rejected.
/// </summary>
public sealed class DateFieldValue : FieldValue
{
    /// <summary>The shared null (unset) date value.</summary>
    public static DateFieldValue Null { get; } = new(null);

    public DateFieldValue(DateTimeOffset? value)
    {
        Value = value;
    }

    public DateTimeOffset? Value { get; }

    public override FieldType Type => FieldType.Date;

    public override bool HasValue => Value.HasValue;

    internal static DateFieldValue ReadJson(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.String)
        {
            throw new JsonException(
                $"a 'date' field value must be an ISO 8601 date/time string but was '{value.ValueKind}'.");
        }

        if (!value.TryGetDateTimeOffset(out DateTimeOffset date))
        {
            throw new JsonException(
                $"'{value.GetString()}' is not a valid ISO 8601 date/time (expected e.g. \"2026-07-02T00:00:00Z\").");
        }

        return new DateFieldValue(date);
    }

    internal override void WriteJson(Utf8JsonWriter writer)
    {
        if (Value is null)
        {
            writer.WriteNullValue();
        }
        else
        {
            // Utf8JsonWriter emits DateTimeOffset in ISO 8601 round-trip format.
            writer.WriteStringValue(Value.Value);
        }
    }
}
