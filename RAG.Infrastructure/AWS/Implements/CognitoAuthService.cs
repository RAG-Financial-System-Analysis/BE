using Amazon.CognitoIdentityProvider;
using Amazon.CognitoIdentityProvider.Model;
using Amazon.Runtime.Internal;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using RAG.Application.Interfaces;

//using RAG.Application.Interfaces;
using RAG.Domain.DTOs.Auth;
using RAG.Domain.Enum;

//using RAG.Domain.Entities;
using RAG.Infrastructure.AWS.Interface;
using RAG.Infrastructure.Database;
using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Infrastructure.AWS.Implements
{
    public class CognitoAuthService : ICognitoAuthService
    {
        private readonly IAmazonCognitoIdentityProvider _cognitoClient;
        private readonly IRoleRepository _roleRepository;
        private readonly IUserRepository _userRepository;
        private readonly string _clientId;
        private readonly string _userPoolId;
        private readonly ApplicationDbContext _context;

        public CognitoAuthService(IAmazonCognitoIdentityProvider cognitoClient, 
                                  IConfiguration configuration,
                                  IUserRepository userRepository,
                                  IRoleRepository roleRepository,
                                  ApplicationDbContext context
            )
        {
            _cognitoClient = cognitoClient;
            _clientId = configuration["AWS:ClientId"];
            _userPoolId = configuration["AWS:UserPoolId"];
            _userRepository = userRepository;
            _roleRepository = roleRepository;
            _context = context;
        }

        public async Task<AuthResponse> LoginAsync(LoginRequest request)
        {
            var authRequest = new InitiateAuthRequest
            {
                ClientId = _clientId,
                AuthFlow = AuthFlowType.USER_PASSWORD_AUTH,
                AuthParameters = new Dictionary<string, string>
                {
                   { "USERNAME", request.Email },
                   { "PASSWORD", request.Password }
                }
            };

            var response = await _cognitoClient.InitiateAuthAsync(authRequest);

            var userInDb = await _context.Users
                                 .Include(u => u.Role)
                                 .AsNoTracking()
                                 .FirstOrDefaultAsync(u => u.Email == request.Email);

            string roleName = "Member"; 
            string fullName = "User";

            if (userInDb != null)
            {
                roleName = userInDb.Role?.Name ?? "Member";
                fullName = userInDb.FullName;
            }

            return new AuthResponse
            {
                AccessToken = response.AuthenticationResult.AccessToken,
                IdToken = response.AuthenticationResult.IdToken,
                RefreshToken = response.AuthenticationResult.RefreshToken,
                Role = roleName,
                FullName = fullName
            };
        }

        public async Task<string> RegisterAsync(RegisterRequest item)
        {
            var roleMember = await _roleRepository.GetByNameAsync(SystemRoles.Member);

            if (roleMember == null)
            {
                throw new Exception($"Lỗi Critical: Hệ thống chưa có Role '{SystemRoles.Member}'. Vui lòng chạy lệnh SQL insert Role.");
            }
            var signUpRequest = new SignUpRequest
            {
                ClientId = _clientId,
                Username = item.Email,
                Password = item.Password,
                UserAttributes = new List<AttributeType>
        {
            new AttributeType { Name = "email", Value = item.Email },
            new AttributeType { Name = "name", Value = item.FullName }
        }
            };
            var response = await _cognitoClient.SignUpAsync(signUpRequest);
            var userSub = response.UserSub;
            try
            {
                var newUser = new User
                {
                    Id = Guid.NewGuid(),
                    CognitoSub = userSub,
                    Email = item.Email,
                    FullName = item.FullName,
                    RoleId = roleMember.Id,
                    CreatedAt = DateTime.UtcNow.ToLocalTime()
                };

                await _userRepository.AddAsync(newUser);
            }
            catch (Exception ex)
            {
                throw new Exception($"Đăng ký AWS thành công nhưng không thể lưu vào Database: {ex.Message}");
            }

            return userSub;
        }

        public async Task<bool> VerifyEmailAsync(VerifyRequest request)
        {
            var confirmRequest = new ConfirmSignUpRequest
            {
                ClientId = _clientId,
                Username = request.Email,
                ConfirmationCode = request.Code
            };

            var response = await _cognitoClient.ConfirmSignUpAsync(confirmRequest);

            return response.HttpStatusCode == System.Net.HttpStatusCode.OK;
        }
    }
}
