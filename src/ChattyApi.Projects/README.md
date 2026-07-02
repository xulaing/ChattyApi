# ChattyApi.Projects

Model and JSON serialization layer for **Projects**: an expected output structure
(a list of typed fields) plus a collection of input/output examples that conform
to that structure.

Built on `System.Text.Json` (no external dependencies), targeting `net8.0`.

## Design overview

| Type | Responsibility |
|------|----------------|
| `FieldType` / `FieldTypes` | The five supported types and the single source of truth for wire names (`"string"`, ...) and UI display names (`"String"`, ...). |
| `FieldDefinition` | One field of the expected structure (name, type, description). Immutable, validated on construction. |
| `ProjectSchema` | The ordered, uniquely named collection of field definitions. |
| `ExampleField` | One field of an example. Name/type are inherited from the structure and immutable; only the value is editable. |
| `ProjectExample` | One example; created from a schema via `ProjectExample.CreateFor(schema)` / `schema.CreateExample()`. |
| `Project` | Structure + examples. Enforces "every example matches the structure". |
| `Values.FieldValue` (+ 5 subclasses) | Strongly typed value of an example field. Each subclass owns the JSON read/write rules for its type. |
| `Serialization.*JsonConverter` | Custom converters, all built on the generic `JsonObjectConverter<T>` base to avoid duplicated boilerplate. |
| `Serialization.ProjectJsonSerializer` | The facade: `Serialize(...)` / `DeserializeProject(...)` / `DeserializeSchema(...)` / `DeserializeExample(...)`. |

Validation is centralized in `Guard` (model side) and `JsonElementExtensions`
(JSON side); every error message names the offending field, example or property.

Errors surface as:

- `ProjectValidationException` — invalid model input (empty name, duplicate field, malformed list text, schema mismatch, ...).
- `ProjectSerializationException` — invalid JSON payloads.
- Both derive from `ProjectModelException`.

## Wire format

The structure is serialized as an **array** of fields rather than an object keyed
by field name. This preserves the user-defined field order and lets duplicate
names be rejected explicitly instead of being silently overwritten by the JSON
parser:

```json
{
  "name": "Invoice extraction",
  "schema": {
    "fields": [
      { "name": "title",  "type": "string", "description": "The document title" },
      { "name": "amount", "type": "number", "description": "The total amount" }
    ]
  },
  "examples": [
    {
      "values": [
        { "name": "title",  "type": "string", "value": "Invoice #42" },
        { "name": "amount", "type": "number", "value": 12.5 }
      ]
    }
  ]
}
```

### JSON types are strictly preserved

| Field type | JSON representation | Notes |
|------------|--------------------|-------|
| `string` | `"hello"` | |
| `number` | `12.5` (raw number) | Backed by `decimal`; quoted numbers are rejected on read. |
| `boolean` | `true` (raw boolean) | Quoted booleans are rejected on read. |
| `date` | `"2026-07-02T00:00:00+00:00"` | JSON has no date primitive, so dates use the ISO 8601 string convention, strictly validated on read (arbitrary strings are rejected). Backed by `DateTimeOffset`. |
| `list` | `[ { "id": 1 }, "two", 3 ]` (raw array) | See below. |

Any value may be `null` (or the `"value"` property may be omitted); names and
types are always required.

### The `list` type

The user types a JSON array into a text box, so the value lives in memory as
text (`ListFieldValue.RawJson`):

- `ExampleField.SetListText(text)` validates the text is a well-formed JSON
  array and throws a `ProjectValidationException` describing the syntax error
  otherwise.
- On **serialization** the text is parsed and written as a *real JSON array*,
  never as a quoted string.
- On **deserialization** the array is re-rendered as indented JSON text
  (`ExampleField.GetListText()`) ready to display in the text box again.

## Usage

```csharp
using ChattyApi.Projects;
using ChattyApi.Projects.Serialization;

var schema = new ProjectSchema(
    new FieldDefinition("title",  FieldType.String, "The document title"),
    new FieldDefinition("amount", FieldType.Number, "The total amount"),
    new FieldDefinition("items",  FieldType.List,   "The line items"));

var project = new Project("Invoice extraction", schema);

ProjectExample example = project.AddExample(); // fields mirror the schema
example.GetField("title").SetString("Invoice #42");
example.GetField("amount").SetNumber(12.5m);
example.GetField("items").SetListText("""[ { "id": 1 }, { "id": 2 } ]""");

string json = ProjectJsonSerializer.Serialize(project);
Project restored = ProjectJsonSerializer.DeserializeProject(json);
```

## Building and testing

```bash
dotnet build src/ChattyApi.Projects
dotnet test tests/ChattyApi.Projects.Tests
```
