using ChattyApi.Projects;
using ChattyApi.Projects.Serialization;
using ChattyApi.Projects.Values;
using Xunit;

namespace ChattyApi.Projects.Tests;

public sealed class ValidationTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void FieldDefinition_RejectsInvalidName(string? name)
    {
        var ex = Assert.Throws<ProjectValidationException>(
            () => new FieldDefinition(name!, FieldType.String, "description"));

        Assert.Contains("Field name", ex.Message);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public void FieldDefinition_RejectsInvalidDescription(string? description)
    {
        var ex = Assert.Throws<ProjectValidationException>(
            () => new FieldDefinition("field1", FieldType.String, description!));

        Assert.Contains("Description of field 'field1'", ex.Message);
    }

    [Fact]
    public void FieldDefinition_RejectsUndefinedType()
    {
        Assert.Throws<ProjectValidationException>(
            () => new FieldDefinition("field1", (FieldType)999, "description"));
    }

    [Fact]
    public void Schema_RejectsDuplicateFieldNames()
    {
        var ex = Assert.Throws<ProjectValidationException>(() => new ProjectSchema(
            new FieldDefinition("field1", FieldType.String, "a"),
            new FieldDefinition("field1", FieldType.Number, "b")));

        Assert.Contains("'field1'", ex.Message);
        Assert.Contains("unique", ex.Message);
    }

    [Fact]
    public void ExampleField_RejectsValueOfWrongType()
    {
        var schema = new ProjectSchema(new FieldDefinition("amount", FieldType.Number, "d"));
        ProjectExample example = schema.CreateExample();

        var ex = Assert.Throws<ProjectValidationException>(
            () => example.GetField("amount").SetString("not a number"));

        Assert.Contains("'amount'", ex.Message);
        Assert.Contains("'number'", ex.Message);
        Assert.Contains("'string'", ex.Message);
    }

    [Fact]
    public void SetListText_RejectsMalformedJson()
    {
        var schema = new ProjectSchema(new FieldDefinition("items", FieldType.List, "d"));
        ProjectExample example = schema.CreateExample();

        var ex = Assert.Throws<ProjectValidationException>(
            () => example.GetField("items").SetListText("[ { not json }"));

        Assert.Contains("'items'", ex.Message);
        Assert.Contains("must be valid JSON", ex.Message);
    }

    [Fact]
    public void SetListText_RejectsNonArrayJson()
    {
        var schema = new ProjectSchema(new FieldDefinition("items", FieldType.List, "d"));
        ProjectExample example = schema.CreateExample();

        var ex = Assert.Throws<ProjectValidationException>(
            () => example.GetField("items").SetListText("""{ "a": 1 }"""));

        Assert.Contains("must be a JSON array", ex.Message);
    }

    [Fact]
    public void SetListText_AcceptsBlankAsNull()
    {
        var schema = new ProjectSchema(new FieldDefinition("items", FieldType.List, "d"));
        ProjectExample example = schema.CreateExample();

        example.GetField("items").SetListText("   ");

        Assert.False(example.GetField("items").Value.HasValue);
        Assert.Null(example.GetField("items").GetListText());
    }

    [Fact]
    public void GetField_UnknownName_ListsKnownFields()
    {
        var schema = new ProjectSchema(new FieldDefinition("field1", FieldType.String, "d"));

        var ex = Assert.Throws<ProjectValidationException>(() => schema.GetField("nope"));

        Assert.Contains("'nope'", ex.Message);
        Assert.Contains("'field1'", ex.Message);
    }

    [Fact]
    public void AddExample_RejectsExampleNotMatchingSchema()
    {
        var schemaA = new ProjectSchema(new FieldDefinition("field1", FieldType.String, "d"));
        var schemaB = new ProjectSchema(new FieldDefinition("other", FieldType.Number, "d"));
        var project = new Project("Demo", schemaA);

        var ex = Assert.Throws<ProjectValidationException>(
            () => project.AddExample(ProjectExample.CreateFor(schemaB)));

        Assert.Contains("does not match the expected output structure", ex.Message);
    }

    [Fact]
    public void Deserialize_UnsupportedFieldType_ExplainsSupportedTypes()
    {
        const string json = """{ "fields": [ { "name": "field1", "type": "integer", "description": "d" } ] }""";

        var ex = Assert.Throws<ProjectSerializationException>(
            () => ProjectJsonSerializer.DeserializeSchema(json));

        Assert.Contains("'integer'", ex.Message);
        Assert.Contains("not a supported field type", ex.Message);
    }

    [Fact]
    public void Deserialize_QuotedNumber_IsRejected()
    {
        const string json = """{ "values": [ { "name": "field1", "type": "number", "value": "12" } ] }""";

        var ex = Assert.Throws<ProjectSerializationException>(
            () => ProjectJsonSerializer.DeserializeExample(json));

        Assert.Contains("'field1'", ex.Message);
        Assert.Contains("raw JSON number", ex.Message);
    }

    [Fact]
    public void Deserialize_InvalidDateString_IsRejected()
    {
        const string json = """{ "values": [ { "name": "field1", "type": "date", "value": "not a date" } ] }""";

        var ex = Assert.Throws<ProjectSerializationException>(
            () => ProjectJsonSerializer.DeserializeExample(json));

        Assert.Contains("ISO 8601", ex.Message);
    }

    [Fact]
    public void Deserialize_ListAsQuotedString_IsRejected()
    {
        const string json = """{ "values": [ { "name": "field1", "type": "list", "value": "[1, 2]" } ] }""";

        var ex = Assert.Throws<ProjectSerializationException>(
            () => ProjectJsonSerializer.DeserializeExample(json));

        Assert.Contains("raw JSON array", ex.Message);
    }

    [Fact]
    public void Deserialize_MalformedJson_IsRejected()
    {
        var ex = Assert.Throws<ProjectSerializationException>(
            () => ProjectJsonSerializer.DeserializeProject("{ not json"));

        Assert.Contains("invalid", ex.Message);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public void Deserialize_NullOrEmptyInput_IsRejected(string? json)
    {
        var ex = Assert.Throws<ProjectSerializationException>(
            () => ProjectJsonSerializer.DeserializeProject(json!));

        Assert.Contains("null or empty", ex.Message);
    }

    [Fact]
    public void Deserialize_ProjectWithExampleMissingField_IsRejected()
    {
        const string json = """
        {
          "name": "Demo",
          "schema": { "fields": [ { "name": "field1", "type": "string", "description": "d" } ] },
          "examples": [ { "values": [] } ]
        }
        """;

        var ex = Assert.Throws<ProjectSerializationException>(
            () => ProjectJsonSerializer.DeserializeProject(json));

        Assert.Contains("field 'field1' is missing", ex.Message);
    }

    [Fact]
    public void DeserializeExample_AgainstSchema_RejectsTypeMismatch()
    {
        var schema = new ProjectSchema(new FieldDefinition("field1", FieldType.Number, "d"));
        const string json = """{ "values": [ { "name": "field1", "type": "string", "value": "x" } ] }""";

        var ex = Assert.Throws<ProjectSerializationException>(
            () => ProjectJsonSerializer.DeserializeExample(json, schema));

        Assert.Contains("does not match", ex.Message);
    }

    [Fact]
    public void FieldTypes_Parse_IsStrict()
    {
        Assert.Equal(FieldType.List, FieldTypes.Parse("list"));
        Assert.Throws<ProjectValidationException>(() => FieldTypes.Parse("List"));
        Assert.Throws<ProjectValidationException>(() => FieldTypes.Parse(null));
    }
}
