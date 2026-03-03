using Amazon.CognitoIdentityProvider;
using Amazon.CognitoIdentityProvider.Model;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using RAG.Domain;
using RAG.Domain.Enum;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace RAG.Infrastructure.Database
{
    public class DbInitializer
    {
        private readonly ApplicationDbContext _context;
        private readonly IAmazonCognitoIdentityProvider _cognitoClient;
        private readonly IConfiguration _configuration;
        private readonly ILogger<DbInitializer> _logger;

        public DbInitializer(
            ApplicationDbContext context,
            IAmazonCognitoIdentityProvider cognitoClient,
            IConfiguration configuration,
            ILogger<DbInitializer> logger)
        {
            _context = context;
            _cognitoClient = cognitoClient;
            _configuration = configuration;
            _logger = logger;
        }

        public async Task InitializeAsync()
        {
            var userPoolId = _configuration["AWS:UserPoolId"];
            var clientId = _configuration["AWS:ClientId"];

            if (string.IsNullOrEmpty(userPoolId) || string.IsNullOrEmpty(clientId))
            {
                _logger.LogWarning("AWS Cognito UserPoolId/ClientId is missing. Skipping Account Seed.");
                return;
            }

            // 1. Ensure Roles exist
            var roles = new List<Role>
            {
                new Role { Id = Guid.NewGuid(), Name = SystemRoles.Admin, Description = "Administrator role", Createdat = DateTime.UtcNow },
                new Role { Id = Guid.NewGuid(), Name = SystemRoles.Analyst, Description = "Analyst role", Createdat = DateTime.UtcNow }
            };

            foreach (var role in roles)
            {
                if (!await _context.Roles.AnyAsync(r => r.Name == role.Name))
                {
                    await _context.Roles.AddAsync(role);
                    _logger.LogInformation($"Role '{role.Name}' seeded to database.");
                }
            }
            await _context.SaveChangesAsync();

            // 2. Define default users
            var defaultUsers = new[]
            {
                new { Email = _configuration["AdminUser:Email"] ?? "admin@rag.com", Password = _configuration["AdminUser:Password"] ?? "Admin@123!!", FullName = _configuration["AdminUser:FullName"] ?? "System Admin", Role = SystemRoles.Admin },
                new { Email = _configuration["AnalystUser:Email"] ?? "analyst@rag.com", Password = _configuration["AnalystUser:Password"] ?? "Analyst@123!!", FullName = _configuration["AnalystUser:FullName"] ?? "System Analyst", Role = SystemRoles.Analyst }
            };

            foreach (var defaultUser in defaultUsers)
            {
                await EnsureUserExistsAsync(defaultUser.Email, defaultUser.Password, defaultUser.FullName, defaultUser.Role, userPoolId, clientId);
            }
        }

        private async Task EnsureUserExistsAsync(string email, string password, string fullName, string roleName, string userPoolId, string clientId)
        {
            var role = await _context.Roles.FirstOrDefaultAsync(r => r.Name == roleName);
            if (role == null)
            {
                _logger.LogError($"Role '{roleName}' not found in DB.");
                return;
            }

            bool existsInCognito = false;
            string cognitoSub = null;
            
            // Check Cognito
            try
            {
                var getUserRequest = new AdminGetUserRequest
                {
                    UserPoolId = userPoolId,
                    Username = email
                };
                var userResponse = await _cognitoClient.AdminGetUserAsync(getUserRequest);
                existsInCognito = true;
                foreach (var attr in userResponse.UserAttributes)
                {
                    if (attr.Name == "sub")
                    {
                        cognitoSub = attr.Value;
                        break;
                    }
                }
            }
            catch (UserNotFoundException)
            {
                existsInCognito = false;
            }
            catch (Exception ex)
            {
                _logger.LogError($"Error checking user '{email}' in Cognito: {ex.Message}");
            }

            // Check DB
            var userInDb = await _context.Users.FirstOrDefaultAsync(u => u.Email == email);
            bool existsInDb = userInDb != null;

            if (existsInDb && existsInCognito)
            {
                _logger.LogInformation($"User '{email}' already exists in both DB and Cognito.");
                // Sync Sub if missed
                if (string.IsNullOrEmpty(userInDb.Cognitosub) && !string.IsNullOrEmpty(cognitoSub))
                {
                    userInDb.Cognitosub = cognitoSub;
                    _context.Users.Update(userInDb);
                    await _context.SaveChangesAsync();
                }
                return;
            }

            // 3. Create in Cognito if not exists
            if (!existsInCognito)
            {
                try
                {
                    var signUpRequest = new SignUpRequest
                    {
                        ClientId = clientId,
                        Username = email,
                        Password = password,
                        UserAttributes = new List<AttributeType>
                        {
                            new AttributeType { Name = "email", Value = email },
                            new AttributeType { Name = "name", Value = fullName }
                        }
                    };
                    
                    var signUpResponse = await _cognitoClient.SignUpAsync(signUpRequest);
                    cognitoSub = signUpResponse.UserSub;

                    // Automatically confirm the user
                    var confirmRequest = new AdminConfirmSignUpRequest
                    {
                        UserPoolId = userPoolId,
                        Username = email
                    };
                    await _cognitoClient.AdminConfirmSignUpAsync(confirmRequest);

                    _logger.LogInformation($"User '{email}' created in Cognito with Sub: {cognitoSub}");
                }
                catch (UsernameExistsException)
                {
                    _logger.LogWarning($"User '{email}' already exists in Cognito despite UserNotFound earlier.");
                    return; // Abort DB insertion to try again next run.
                }
                catch (Exception ex)
                {
                    _logger.LogError($"Failed to create user '{email}' in Cognito: {ex.Message}");
                    return; // Stop if Cognito creation fails to keep them synced
                }
            }

            // 4. Create in DB if not exists
            if (!existsInDb)
            {
                if (string.IsNullOrEmpty(cognitoSub))
                {
                    try
                    {
                        var userResponse = await _cognitoClient.AdminGetUserAsync(new AdminGetUserRequest { UserPoolId = userPoolId, Username = email });
                        foreach (var attr in userResponse.UserAttributes)
                        {
                            if (attr.Name == "sub")
                            {
                                cognitoSub = attr.Value;
                                break;
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError($"Failed to fetch Sub for user '{email}' from Cognito: {ex.Message}");
                    }
                }

                var newUser = new User
                {
                    Id = Guid.NewGuid(),
                    Email = email,
                    Fullname = fullName,
                    Roleid = role.Id,
                    Cognitosub = cognitoSub,
                    Createdat = DateTime.UtcNow,
                    Isactive = true
                };

                await _context.Users.AddAsync(newUser);
                await _context.SaveChangesAsync();
                _logger.LogInformation($"User '{email}' created in Database.");
            }
            else if (existsInDb && string.IsNullOrEmpty(userInDb.Cognitosub) && !string.IsNullOrEmpty(cognitoSub))
            {
                userInDb.Cognitosub = cognitoSub;
                _context.Users.Update(userInDb);
                await _context.SaveChangesAsync();
                _logger.LogInformation($"User '{email}' updated with Cognito Sub in Database.");
            }
        }
    }

    public static class DbInitializerExtension
    {
        public static async Task UseDbInitializer(this IServiceProvider serviceProvider)
        {
            using var scope = serviceProvider.CreateScope();
            var initializer = scope.ServiceProvider.GetRequiredService<DbInitializer>();
            await initializer.InitializeAsync();
        }
    }
}
