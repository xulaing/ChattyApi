using System.Text.Json;

namespace ChattyApi.Projects.Values;

/// <summary>A boolean value, serialized as a raw JSON boolean (<c>true</c> / <c>false</c>, never <c>"true"</c>).</summary>
public sealed class BooleanFieldValue : FieldValue
{
    /// <summary>The shared null (unset) boolean value.</summary>
    public static BooleanFieldValue Null { get; } = new(null);

    public BooleanFieldValue(bool? value)
    {
        Value = value;
    }

    public bool? Value { get; }

    public override FieldType Type => FieldType.Boolean;

    public override bool HasValue => Value.HasValue;

    internal static BooleanFieldValue ReadJson(JsonElement value)
    {
        if (value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
        {
            throw new JsonException(
                $"a 'boolean' field value must be a raw JSON boolean (true/false) but was '{value.ValueKind}'.");
        }

        return new BooleanFieldValue(value.GetBoolean());
    }

    internal override void WriteJson(Utf8JsonWriter writer)
    {
        if (Value is null)
        {
            writer.WriteNullValue();
        }
        else
        {
            writer.WriteBooleanValue(Value.Value);
        }
    }
}
