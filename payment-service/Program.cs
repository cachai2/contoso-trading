using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;
using OpenTelemetry.Resources;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddApplicationInsightsTelemetry();
// Dynatrace OTLP export — traces + metrics + logs (active when DT_OTLP_ENDPOINT is set)
var dtEndpoint = Environment.GetEnvironmentVariable("DT_OTLP_ENDPOINT");
var dtToken = Environment.GetEnvironmentVariable("DT_OTLP_TOKEN");
if (!string.IsNullOrEmpty(dtEndpoint))
{
    var baseOtlp = dtEndpoint.TrimEnd('/');
    Action<OpenTelemetry.Exporter.OtlpExporterOptions> configureOtlp(string signal) => o =>
    {
        o.Endpoint = new Uri($"{baseOtlp}/v1/{signal}");
        o.Headers = $"Authorization=Api-Token {dtToken}";
        o.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.HttpProtobuf;
    };

    builder.Services.AddOpenTelemetry()
        .ConfigureResource(r => r.AddService("payment-service"))
        .WithTracing(tracing => tracing
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddOtlpExporter(configureOtlp("traces")))
        .WithMetrics(metrics => metrics
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddOtlpExporter(configureOtlp("metrics")));

    builder.Logging.AddOpenTelemetry(logging =>
    {
        logging.IncludeScopes = true;
        logging.IncludeFormattedMessage = true;
        logging.AddOtlpExporter(configureOtlp("logs"));
    });
}

var app = builder.Build();
var logger = app.Logger;

// CRITICAL: DATABASE_URL must be a secretRef pointing to db-conn secret.
// If missing/empty, the service falls into MOCK MODE — a silent data integrity failure
// where bookings appear to succeed but are never persisted to PostgreSQL.
var dbConn = Environment.GetEnvironmentVariable("DATABASE_URL") ?? "";
var poolLimit = Environment.GetEnvironmentVariable("POOL_LIMIT");
if (!string.IsNullOrEmpty(dbConn) && !string.IsNullOrEmpty(poolLimit))
    dbConn += $";Maximum Pool Size={poolLimit}";

var dbMode = string.IsNullOrEmpty(dbConn) ? "mock" : "database";
if (dbMode == "mock")
    logger.LogWarning("PAYMENT-SERVICE STARTING IN MOCK MODE — DATABASE_URL is not set. " +
        "Bookings will NOT be persisted. This is a DATA INTEGRITY risk in production.");
else
    logger.LogInformation("Payment-service starting in database mode. Pool limit: {PoolLimit}", poolLimit ?? "default");

app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "payment-service", dataMode = dbMode }));

app.MapGet("/payments", async () =>
{
    try
    {
        if (string.IsNullOrEmpty(dbConn))
            return Results.Ok(new { payments = new[] { new { id = 1, amount = 99.99, status = "completed" } }, source = "mock" });

        await using var conn = new NpgsqlConnection(dbConn);
        await conn.OpenAsync();
        return Results.Ok(new { payments = new[] { new { id = 1, amount = 99.99, status = "completed" } }, source = "database" });
    }
    catch (Exception ex)
    {
        return Results.Problem($"Database error: {ex.Message}", statusCode: 500);
    }
});

app.MapPost("/payments/process", async () =>
{
    // Simulate payment processing with occasional failures
    await Task.Delay(Random.Shared.Next(100, 500));
    if (Random.Shared.Next(100) < 5) // 5% failure rate
        return Results.Problem("Payment gateway timeout", statusCode: 504);
    return Results.Ok(new { status = "processed", transactionId = Guid.NewGuid() });
});

app.Run();
