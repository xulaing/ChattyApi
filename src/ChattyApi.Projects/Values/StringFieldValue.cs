using System.Text.Json;

namespace ChattyApi.Projects.Values;

/// <summary>A string value, serialized as a JSON string (e.g. <c>"hello"</c>).</summary>
public sealed class StringFieldValue : FieldValue
{
    /// <summary>The shared null (unset) string value.</summary>
    public static StringFieldValue Null { get; } = new(null);

    public StringFieldValue(string? value)
    {
        Value = value;
    }

    public string? Value { get; }

    public override FieldType Type => FieldType.String;

    public override bool HasValue => Value is not null;

    internal static StringFieldValue ReadJson(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.String)
        {
            throw new JsonException(
                $"a 'string' field value must be a JSON string but was '{value.ValueKind}'.");
        }

        return new StringFieldValue(value.GetString());
    }

    internal override void WriteJson(Utf8JsonWriter writer)
    {
        if (Value is null)
        {
            writer.WriteNullValue();
        }
        else
        {
            writer.WriteStringValue(Value);
        }
    }
}
