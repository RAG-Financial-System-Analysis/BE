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
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", b =>
    {
        b.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
    });
});
//AWS Lambda
builder.Services.AddAWSLambdaHosting(LambdaEventSource.HttpApi);

var app = builder.Build();

// Run Database Initializer
await app.Services.UseDbInitializer();

// 4. Swagger Configuration
// Trên AWS Lambda API Gateway, môi trường thường là Production, nên ta mở luôn hoặc dùng cờ tự định nghĩa.
// if (app.Environment.IsDevelopment() || app.Environment.IsProduction()) -> Tạm thời mở luôn cho dễ test
app.UseSwagger(c => c.RouteTemplate = "swagger/{documentName}/swagger.json"); 

app.UseSwaggerUI(c =>
{
    c.InjectStylesheet("/custom-swagger.css");
    
    // Rất quan trọng cho API Gateway:
    c.SwaggerEndpoint("v1/swagger.json", "RAG API V1");
    // API Gateway thường chèn tên stage (VD: /Prod).
    // Đặt Prefix rỗng hoặc theo stage để tránh lỗi 404 trang Swagger Not Found.
    c.RoutePrefix = "swagger"; 
}); 

app.UseStaticFiles();
app.UseCors("AllowAll");
app.UseHttpsRedirection();

app.UseAuthentication();
app.UseAuthorization();
 
app.MapControllers();

app.Run();
