using System.Text.Json;
using System.Text.Json.Nodes;
using ChattyApi.Projects;
using ChattyApi.Projects.Serialization;
using ChattyApi.Projects.Values;
using Xunit;

namespace ChattyApi.Projects.Tests;

public sealed class SerializationTests
{
    private static Project CreateSampleProject()
    {
        var schema = new ProjectSchema(
            new FieldDefinition("title", FieldType.String, "The document title"),
            new FieldDefinition("amount", FieldType.Number, "The total amount"),
            new FieldDefinition("approved", FieldType.Boolean, "Whether it was approved"),
            new FieldDefinition("issuedOn", FieldType.Date, "The issue date"),
            new FieldDefinition("items", FieldType.List, "The line items"));

        var project = new Project("Invoice extraction", schema);

        ProjectExample example = project.AddExample();
        example.GetField("title").SetString("Invoice #42");
        example.GetField("amount").SetNumber(12.5m);
        example.GetField("approved").SetBoolean(true);
        example.GetField("issuedOn").SetDate(new DateTimeOffset(2026, 7, 2, 0, 0, 0, TimeSpan.Zero));
        example.GetField("items").SetListText("""[ { "id": 1 }, "two", 3 ]""");

        return project;
    }

    [Fact]
    public void Serialize_PreservesNativeJsonTypes()
    {
        string json = ProjectJsonSerializer.Serialize(CreateSampleProject());

        using JsonDocument document = JsonDocument.Parse(json);
        JsonElement values = document.RootElement.GetProperty("examples")[0].GetProperty("values");

        Assert.Equal(JsonValueKind.String, values[0].GetProperty("value").ValueKind);
        Assert.Equal(JsonValueKind.Number, values[1].GetProperty("value").ValueKind);
        Assert.Equal(12.5m, values[1].GetProperty("value").GetDecimal());
        Assert.Equal(JsonValueKind.True, values[2].GetProperty("value").ValueKind);

        // Dates are ISO 8601 strings that parse back exactly.
        JsonElement dateValue = values[3].GetProperty("value");
        Assert.Equal(JsonValueKind.String, dateValue.ValueKind);
        Assert.Equal(new DateTimeOffset(2026, 7, 2, 0, 0, 0, TimeSpan.Zero), dateValue.GetDateTimeOffset());

        // The list is a real JSON array, not a quoted string.
        Assert.Equal(JsonValueKind.Array, values[4].GetProperty("value").ValueKind);
        Assert.Equal(3, values[4].GetProperty("value").GetArrayLength());
    }

    [Fact]
    public void RoundTrip_RestoresAllValues()
    {
        Project original = CreateSampleProject();
        string json = ProjectJsonSerializer.Serialize(original);
        Project restored = ProjectJsonSerializer.DeserializeProject(json);

        Assert.Equal(original.Name, restored.Name);
        Assert.Equal(original.Schema.Count, restored.Schema.Count);
        Assert.Equal("The total amount", restored.Schema.GetField("amount").Description);

        ProjectExample example = Assert.Single(restored.Examples);
        Assert.Equal("Invoice #42", Assert.IsType<StringFieldValue>(example.GetField("title").Value).Value);
        Assert.Equal(12.5m, Assert.IsType<NumberFieldValue>(example.GetField("amount").Value).Value);
        Assert.Equal(true, Assert.IsType<BooleanFieldValue>(example.GetField("approved").Value).Value);
        Assert.Equal(
            new DateTimeOffset(2026, 7, 2, 0, 0, 0, TimeSpan.Zero),
            Assert.IsType<DateFieldValue>(example.GetField("issuedOn").Value).Value);
    }

    [Fact]
    public void RoundTrip_ListValue_ComesBackAsEquivalentTextForTheTextBox()
    {
        Project original = CreateSampleProject();
        string json = ProjectJsonSerializer.Serialize(original);
        Project restored = ProjectJsonSerializer.DeserializeProject(json);

        string? listText = restored.Examples[0].GetField("items").GetListText();

        Assert.NotNull(listText);
        Assert.True(JsonNode.DeepEquals(
            JsonNode.Parse("""[ { "id": 1 }, "two", 3 ]"""),
            JsonNode.Parse(listText)));
    }

    [Fact]
    public void Deserialize_HandWrittenJson_Works()
    {
        const string json = """
        {
          "name": "Demo",
          "schema": {
            "fields": [
              { "name": "field1", "type": "string", "description": "description 1" },
              { "name": "field2", "type": "number", "description": "description 2" }
            ]
          },
          "examples": [
            {
              "values": [
                { "name": "field1", "type": "string", "value": "example value" },
                { "name": "field2", "type": "number", "value": 12 }
              ]
            }
          ]
        }
        """;

        Project project = ProjectJsonSerializer.DeserializeProject(json);

        Assert.Equal(2, project.Schema.Count);
        Assert.Equal(FieldType.Number, project.Schema.GetField("field2").Type);
        Assert.Equal(12m, Assert.IsType<NumberFieldValue>(project.Examples[0].GetField("field2").Value).Value);
    }

    [Fact]
    public void RoundTrip_NullValues_AreAllowedAndPreserved()
    {
        var schema = new ProjectSchema(new FieldDefinition("field1", FieldType.Number, "A number"));
        var project = new Project("Demo", schema);
        project.AddExample(); // value left unset

        Project restored = ProjectJsonSerializer.DeserializeProject(ProjectJsonSerializer.Serialize(project));

        Assert.False(restored.Examples[0].GetField("field1").Value.HasValue);
    }

    [Fact]
    public void Deserialize_MissingValueProperty_IsTreatedAsNull()
    {
        const string json = """{ "values": [ { "name": "field1", "type": "boolean" } ] }""";

        ProjectExample example = ProjectJsonSerializer.DeserializeExample(json);

        Assert.False(example.GetField("field1").Value.HasValue);
    }

    [Fact]
    public void SchemaRoundTrip_PreservesFieldOrder()
    {
        var schema = new ProjectSchema(
            new FieldDefinition("zeta", FieldType.String, "z"),
            new FieldDefinition("alpha", FieldType.Number, "a"));

        ProjectSchema restored = ProjectJsonSerializer.DeserializeSchema(ProjectJsonSerializer.Serialize(schema));

        Assert.Equal(new[] { "zeta", "alpha" }, restored.Fields.Select(f => f.Name));
    }
}
