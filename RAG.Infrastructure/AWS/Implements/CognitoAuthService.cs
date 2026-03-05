using Amazon.CognitoIdentityProvider;
using Amazon.CognitoIdentityProvider.Model;
using Amazon.Runtime.Internal;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using RAG.Application.Interfaces;
using RAG.Domain;
using RAG.Domain.DTOs.Auth;
using RAG.Domain.Enum;
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
                fullName = userInDb.Fullname;
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
            var roleMember = await _roleRepository.GetByNameAsync(SystemRoles.Analyst);

            if (roleMember == null)
            {
                throw new Exception($"Lỗi Critical: Hệ thống chưa có Role '{SystemRoles.Analyst}'. Vui lòng chạy lệnh SQL insert Role.");
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
                    Cognitosub = userSub,
                    Email = item.Email,
                    Fullname = item.FullName,
                    Roleid = roleMember.Id,
                    Createdat = DateTime.UtcNow.ToLocalTime()
                };

                await _userRepository.AddAsync(newUser);
            }
            catch (Exception ex)
            {
                // Thực hiện Rollback trên Cognito (Xóa tài khoản vừa tạo)
                try
                {
                    var deleteRequest = new AdminDeleteUserRequest
                    {
                        UserPoolId = _userPoolId,
                        Username = item.Email
                    };
                    await _cognitoClient.AdminDeleteUserAsync(deleteRequest);
                }
                catch (Exception rollbackEx)
                {
                    // Trường hợp tồi tệ nhất: Cả DB và việc Rollback đều thất bại
                    throw new Exception($"Đăng ký AWS thành công nhưng lưu vào Database thất bại. ĐÃ XẢY RA LỖI KHI ROLLBACK TÀI KHOẢN COGNITO: DB Error ({ex.Message}), Rollback Error ({rollbackEx.Message})");
                }

                throw new Exception($"Không thể lưu vào Database, đã Rollback (xóa) tài khoản trên Cognito thành công. DB Error: {ex.Message}");
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

        public async Task<bool> LogoutAsync(string accessToken)
        {
            var signOutRequest = new GlobalSignOutRequest
            {
                AccessToken = accessToken
            };

            var response = await _cognitoClient.GlobalSignOutAsync(signOutRequest);
            return response.HttpStatusCode == System.Net.HttpStatusCode.OK;
        }
    }
}
