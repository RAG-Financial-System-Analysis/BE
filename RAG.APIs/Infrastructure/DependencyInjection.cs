using Amazon.CognitoIdentityProvider;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using RAG.Application.Interfaces;
using RAG.Application.Interfaces.OpenAI;
using RAG.Application.Interfaces.Pdfs;
using RAG.Infrastructure.AWS.Implements;
using RAG.Infrastructure.AWS.Interface;
using RAG.Infrastructure.Database;
using RAG.Infrastructure.Security;
using RAG.Infrastructure.Services;
//using RAG.Infrastructure.Database;

namespace RAG.APIs.Infrastructure
{
    public static class DependencyInjection
    {
        public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
        {
            var connectionString = configuration.GetConnectionString("DefaultConnection");
            services.AddDbContext<ApplicationDbContext>(options =>
                options.UseNpgsql(connectionString));
            
            var awsOptions = configuration.GetAWSOptions();
            var accessKey = configuration["AWS:AccessKey"];
            var secretKey = configuration["AWS:SecretKey"];
            
            // ✅ FIXED: Set credentials only once
            if (!string.IsNullOrEmpty(accessKey) && !string.IsNullOrEmpty(secretKey))
            {
                awsOptions.Credentials = new Amazon.Runtime.BasicAWSCredentials(accessKey, secretKey);
            }

            services.AddDefaultAWSOptions(awsOptions);
            services.AddAWSService<IAmazonCognitoIdentityProvider>();
            services.AddAWSService<Amazon.S3.IAmazonS3>();

            // 3. Đăng ký các Repository và Service
            services.AddScoped<IUserRepository, UserRepository>();
            services.AddScoped<ICognitoAuthService, CognitoAuthService>();
            services.AddScoped<IRoleRepository, RoleRepository>();
            services.AddScoped<ICompanyRepository, CompanyRepository>();
            services.AddScoped<ICompanyService, CompanyService>();
            services.AddScoped<IUserService, UserService>();
            services.AddScoped<IAdminService, AdminService>();
            services.AddScoped<IMetricService, MetricService>();
            services.AddScoped<RAG.Application.Interfaces.Analaytic.IAnalyticsService, AnalyticsService>();
            services.AddScoped<IS3Service, S3Service>();
            services.AddScoped<IPdfExtractService, PdfExtractService>();
            services.AddScoped<IReportService, ReportService>();
            services.AddScoped<IChatService, ChatService>();
            services.AddScoped<IRagService, RagService>();
            
            // NEW: Gemini Service with configurable timeout
            services.AddHttpClient<IGeminiService, GeminiService>(client =>
            {
                // ✅ FIXED: Use Gemini specific timeout and ensure it's long enough for PDF processing
                var geminiTimeoutMinutes = configuration.GetValue<int>("Gemini:TimeoutMinutes", 15);
                var ragTimeoutMinutes = configuration.GetValue<int>("RAG:RequestTimeoutMinutes", 25);
                
                // Use the longer timeout between Gemini and RAG settings
                var timeoutMinutes = Math.Max(geminiTimeoutMinutes, ragTimeoutMinutes);
                
                client.Timeout = TimeSpan.FromMinutes(timeoutMinutes);
                
                Console.WriteLine($"🔧 Gemini HttpClient timeout set to: {timeoutMinutes} minutes ({timeoutMinutes * 60} seconds)");
            });
            services.AddScoped<IGeminiService, GeminiService>();
            
            services.AddTransient<IClaimsTransformation, RoleClaimsTransformation>();
            services.AddScoped<DbInitializer>();
            //
            services.AddAuthentication(options =>
            {
                options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
                options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
            })
.AddJwtBearer(options =>
{
    var authorityUrl = configuration["AWS:Authority"];
    options.Authority = authorityUrl;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidIssuer = authorityUrl,
        ValidateAudience = false,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true
    };
});


            return services;
        }
    }
}
