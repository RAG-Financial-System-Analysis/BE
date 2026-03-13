using Amazon.CognitoIdentityProvider;
using Amazon.Extensions.Configuration.SystemsManager;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using RAG.APIs.Infrastructure;
//using RAG.Application.Interfaces;
using RAG.Infrastructure.AWS;
using RAG.Infrastructure.Database;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddInfrastructure(builder.Configuration);

// 3. Tích hợp AWS Systems Manager (Lưu config)
if (!builder.Environment.IsDevelopment())
{
    // You can set up the options to fetch parameters directly from SSM Parameter Store
    builder.Configuration.AddSystemsManager(options =>
    {
        options.Path = "/RagSystem/Prod/"; // Tên đường dẫn config trên AWS Parameter Store
        options.ReloadAfter = TimeSpan.FromMinutes(10);
    });
}

builder.Services.AddControllers();

// Configure request timeout for RAG APIs (configurable)
builder.Services.Configure<IISServerOptions>(options =>
{
    var maxFileSizeMB = builder.Configuration.GetValue<int>("RAG:MaxFileSizeMB", 100);
    options.MaxRequestBodySize = maxFileSizeMB * 1024 * 1024;
});

builder.WebHost.ConfigureKestrel(options =>
{
    var maxFileSizeMB = builder.Configuration.GetValue<int>("RAG:MaxFileSizeMB", 100);
    var timeoutMinutes = builder.Configuration.GetValue<int>("RAG:RequestTimeoutMinutes", 25);
    
    options.Limits.MaxRequestBodySize = maxFileSizeMB * 1024 * 1024;
    options.Limits.RequestHeadersTimeout = TimeSpan.FromMinutes(timeoutMinutes);
    options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(timeoutMinutes);
    
    // ✅ NEW: Add request timeout for long-running operations
    Console.WriteLine($"🔧 Kestrel request timeout set to: {timeoutMinutes} minutes");
});

// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", builder =>
    {
        builder.AllowAnyOrigin()   // Cho phép mọi nguồn (Frontend nào cũng gọi được)
               .AllowAnyMethod()   
               .AllowAnyHeader();  
    });
});

builder.Services.AddSwaggerGen(option =>
{
    option.SwaggerDoc("v1", new OpenApiInfo { Title = "RAG API", Version = "v1" });

    option.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        In = ParameterLocation.Header,
        Description = "Nhập Token: Bearer {token}",
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        BearerFormat = "JWT",
        Scheme = "Bearer"
    });

    option.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            new string[] { }
        }
    });
});

//AWS Lambda
builder.Services.AddAWSLambdaHosting(LambdaEventSource.HttpApi);

var app = builder.Build();

// Run Database Initializer
try
{
    await app.Services.UseDbInitializer();
}
catch (Exception ex)
{
    Console.WriteLine($"DbInitializer failed: {ex.Message}");
    // Continue startup even if DbInitializer fails
}

// 4. Swagger Configuration
app.UseSwagger(c => c.RouteTemplate = "swagger/{documentName}/swagger.json"); 

app.UseSwaggerUI(c =>
{
    c.InjectStylesheet("/custom-swagger.css");
    c.SwaggerEndpoint("v1/swagger.json", "RAG API V1");
    c.RoutePrefix = "swagger"; 
}); 

app.UseStaticFiles();
app.UseCors("AllowAll");
app.UseHttpsRedirection();

app.UseAuthentication();
app.UseAuthorization();
 
app.MapControllers();

app.Run();

// Lambda Entry Point for AWS Lambda deployment
public class LambdaEntryPoint : Amazon.Lambda.AspNetCoreServer.APIGatewayProxyFunction
{
    protected override void Init(IWebHostBuilder builder)
    {
        builder
            .UseContentRoot(Directory.GetCurrentDirectory())
            .UseStartup<Startup>();
    }
}

public class Startup
{
    public IConfiguration Configuration { get; }

    public Startup(IConfiguration configuration)
    {
        Configuration = configuration;
    }

    public void ConfigureServices(IServiceCollection services)
    {
        services.AddInfrastructure(Configuration);

        // 3. Tích hợp AWS Systems Manager (Lưu config)
        if (!Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT")?.Equals("Development", StringComparison.OrdinalIgnoreCase) == true)
        {
            // AWS Systems Manager configuration would go here
        }

        services.AddControllers();
        services.AddEndpointsApiExplorer();
        services.AddSwaggerGen();

        services.AddCors(options =>
        {
            options.AddPolicy("AllowAll", builder =>
            {
                builder.AllowAnyOrigin()
                       .AllowAnyMethod()
                       .AllowAnyHeader();
            });
        });

        services.AddSwaggerGen(option =>
        {
            option.SwaggerDoc("v1", new OpenApiInfo { Title = "RAG API", Version = "v1" });

            option.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
            {
                In = ParameterLocation.Header,
                Description = "Nhập Token: Bearer {token}",
                Name = "Authorization",
                Type = SecuritySchemeType.Http,
                BearerFormat = "JWT",
                Scheme = "Bearer"
            });

            option.AddSecurityRequirement(new OpenApiSecurityRequirement
            {
                {
                    new OpenApiSecurityScheme
                    {
                        Reference = new OpenApiReference
                        {
                            Type = ReferenceType.SecurityScheme,
                            Id = "Bearer"
                        }
                    },
                    new string[] { }
                }
            });
        });
    }

    public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
    {
        // Run Database Initializer
        using (var scope = app.ApplicationServices.CreateScope())
        {
            try
            {
                scope.ServiceProvider.UseDbInitializer().Wait();
            }
            catch (Exception ex)
            {
                // Log error but don't fail startup
                Console.WriteLine($"DbInitializer failed: {ex.Message}");
            }
        }

        app.UseSwagger(c => c.RouteTemplate = "swagger/{documentName}/swagger.json");

        app.UseSwaggerUI(c =>
        {
            c.SwaggerEndpoint("v1/swagger.json", "RAG API V1");
            c.RoutePrefix = "swagger";
        });

        app.UseStaticFiles();
        app.UseCors("AllowAll");
        app.UseHttpsRedirection();

        app.UseAuthentication();
        app.UseAuthorization();

        app.UseRouting();
        app.UseEndpoints(endpoints =>
        {
            endpoints.MapControllers();
        });
    }
}
