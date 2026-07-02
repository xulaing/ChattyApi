using System.Text.Json;
using ChattyApi.Projects.Serialization;

namespace ChattyApi.Projects.Values;

/// <summary>
/// A list value. The user types a JSON array into a text box, so the value is stored
/// internally as text (<see cref="RawJson"/>) — but it is validated to be a well-formed
/// JSON array when created, and it is serialized as a <b>real JSON array</b>, never as a
/// quoted string. On deserialization the array is converted back to indented JSON text
/// so it can be displayed in the text box again.
/// </summary>
public sealed class ListFieldValue : FieldValue
{
    /// <summary>The shared null (unset) list value.</summary>
    public static ListFieldValue Null { get; } = new(null);

    // Private: instances must go through Parse/ReadJson so RawJson is always
    // either null or a validated JSON array.
    private ListFieldValue(string? rawJson)
    {
        RawJson = rawJson;
    }

    /// <summary>
    /// The JSON array as text, exactly as it should appear in the text box,
    /// or null when the value is unset. Always a valid JSON array when non-null.
    /// </summary>
    public string? RawJson { get; }

    public override FieldType Type => FieldType.List;

    public override bool HasValue => RawJson is not null;

    /// <summary>
    /// Creates a list value from the text box content. The text must be a well-formed
    /// JSON array (e.g. <c>[ { }, { } ]</c>); null/blank text yields the null value.
    /// Throws <see cref="ProjectValidationException"/> explaining exactly what is malformed otherwise.
    /// </summary>
    public static ListFieldValue Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return Null;
        }

        JsonValueKind rootKind;
        try
        {
            using JsonDocument document = JsonDocument.Parse(text);
            rootKind = document.RootElement.ValueKind;
        }
        catch (JsonException ex)
        {
            throw new ProjectValidationException(
                $"A 'list' value must be valid JSON. The entered text could not be parsed: {ex.Message}", ex);
        }

        if (rootKind != JsonValueKind.Array)
        {
            throw new ProjectValidationException(
                $"A 'list' value must be a JSON array (e.g. [ ... ]) but the entered text is a JSON '{rootKind}'.");
        }

        return new ListFieldValue(text);
    }

    internal static ListFieldValue ReadJson(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Array)
        {
            throw new JsonException(
                $"a 'list' field value must be a raw JSON array but was '{value.ValueKind}'.");
        }

        // Re-indent so the text box shows nicely formatted JSON.
        return new ListFieldValue(JsonText.FormatIndented(value));
    }

    internal override void WriteJson(Utf8JsonWriter writer)
    {
        if (RawJson is null)
        {
            writer.WriteNullValue();
            return;
        }

        // RawJson is guaranteed valid by Parse/ReadJson; re-parse to emit it as a real array.
        using JsonDocument document = JsonDocument.Parse(RawJson);
        document.RootElement.WriteTo(writer);
    }
}
