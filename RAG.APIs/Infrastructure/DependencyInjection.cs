using Amazon.CognitoIdentityProvider;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using RAG.Application.Interfaces;
using Microsoft.AspNetCore.Authentication;
using RAG.Infrastructure.AWS.Implements;
using RAG.Infrastructure.AWS.Interface;
using RAG.Infrastructure.Database;
using RAG.Infrastructure.Security;
using Microsoft.Extensions.Configuration;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using RAG.Application.Interfaces.Pdfs;
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
            if (!string.IsNullOrEmpty(accessKey) && !string.IsNullOrEmpty(secretKey))
            {
                awsOptions.Credentials = new Amazon.Runtime.BasicAWSCredentials(accessKey, secretKey);
            }

            services.AddDefaultAWSOptions(awsOptions);
            services.AddAWSService<IAmazonCognitoIdentityProvider>();
            if (!string.IsNullOrEmpty(accessKey) && !string.IsNullOrEmpty(secretKey))
            {
                awsOptions.Credentials = new Amazon.Runtime.BasicAWSCredentials(accessKey, secretKey);
            }

            // 3. Đăng ký các Repository và Service
            services.AddScoped<IUserRepository, UserRepository>();
            services.AddScoped<ICognitoAuthService, CognitoAuthService>();
            services.AddScoped<IRoleRepository, RoleRepository>();
            services.AddScoped<ICompanyRepository, CompanyRepository>();
            services.AddScoped<ICompanyService, CompanyService>();
            services.AddScoped<IPdfExtractService, RAG.Infrastructure.Services.PdfExtractService>();
            services.AddScoped<IReportService, RAG.Infrastructure.Services.ReportService>();
            services.AddScoped<IChatService, RAG.Infrastructure.Services.ChatService>();
            services.AddScoped<RAG.Application.Interfaces.OpenAI.IRagService, RAG.Infrastructure.Services.RagService>();
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
