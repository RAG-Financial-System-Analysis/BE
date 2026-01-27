using Amazon.CognitoIdentityProvider;
using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
using RAG.Infrastructure.AWS.Implements;
using RAG.Infrastructure.AWS.Interface;
using RAG.Infrastructure.Database;

namespace RAG.APIs.Infrastructure
{
    public static class DependencyInjection
    {
        public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
        {
            // 1. Cấu hình Database
            var connectionString = configuration.GetConnectionString("DefaultConnection");
            services.AddDbContext<ApplicationDbContext>(options =>
                options.UseNpgsql(connectionString));

            // 2. Cấu hình AWS
            // --- 2. Cấu hình AWS (SỬA LẠI ĐOẠN NÀY) ---
            var awsOptions = configuration.GetAWSOptions();
            var accessKey = configuration["AWS:AccessKey"];
            var secretKey = configuration["AWS:SecretKey"];
            // Kiểm tra nếu có key thì gán cứng vào Options luôn
            if (!string.IsNullOrEmpty(accessKey) && !string.IsNullOrEmpty(secretKey))
            {
                awsOptions.Credentials = new Amazon.Runtime.BasicAWSCredentials(accessKey, secretKey);
            }

            services.AddDefaultAWSOptions(awsOptions);
            services.AddAWSService<IAmazonCognitoIdentityProvider>();
            // Kiểm tra nếu có key thì gán cứng vào Options luôn
            if (!string.IsNullOrEmpty(accessKey) && !string.IsNullOrEmpty(secretKey))
            {
                awsOptions.Credentials = new Amazon.Runtime.BasicAWSCredentials(accessKey, secretKey);
            }

            // 3. Đăng ký các Repository và Service
            services.AddScoped<IUserRepository, UserRepository>();
            services.AddScoped<ICognitoAuthService, CognitoAuthService>();

            return services;
        }
    }
}
