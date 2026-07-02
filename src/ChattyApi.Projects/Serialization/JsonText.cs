using System.Text.Json;

namespace ChattyApi.Projects.Serialization;

/// <summary>Small shared JSON formatting helpers.</summary>
internal static class JsonText
{
    private static readonly JsonSerializerOptions IndentedOptions = new() { WriteIndented = true };

    /// <summary>Renders a JSON element as indented text (used to display list values in the text box).</summary>
    public static string FormatIndented(JsonElement element) =>
        JsonSerializer.Serialize(element, IndentedOptions);
}
