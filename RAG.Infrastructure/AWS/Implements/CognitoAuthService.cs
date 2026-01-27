using Amazon.CognitoIdentityProvider;
using Amazon.CognitoIdentityProvider.Model;
using Amazon.Runtime.Internal;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using RAG.Application.Interfaces;
using RAG.Domain.DTOs.Auth;
using RAG.Domain.Entities;
using RAG.Infrastructure.AWS.Interface;
using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Infrastructure.AWS.Implements
{
    public class CognitoAuthService : ICognitoAuthService
    {
        private readonly IAmazonCognitoIdentityProvider _cognitoClient;
        private readonly IUserRepository _userRepository;
        private readonly string _clientId;
        private readonly string _userPoolId;    

        public CognitoAuthService(IAmazonCognitoIdentityProvider cognitoClient, 
                                  IConfiguration configuration,
                                  IUserRepository userRepository)
        {
            _cognitoClient = cognitoClient;
            _clientId = configuration["AWS:ClientId"];
            _userPoolId = configuration["AWS:UserPoolId"];
            _userRepository = userRepository;
        }

        public async Task<AuthResponse> LoginAsync(LoginRequest request)
        {
            var authRequest = new InitiateAuthRequest
            {
                ClientId = _clientId,
                AuthFlow = AuthFlowType.USER_PASSWORD_AUTH,//đăng nhập với mk + email
                AuthParameters = new Dictionary<string, string>
                {
                   { "USERNAME", request.Email },
                   { "PASSWORD", request.Password }
                }
            };

            var response = await _cognitoClient.InitiateAuthAsync(authRequest);

            return new AuthResponse
            {
                AccessToken = response.AuthenticationResult.AccessToken,
                IdToken = response.AuthenticationResult.IdToken,
                RefreshToken = response.AuthenticationResult.RefreshToken
            };
        }

        public async Task<string> RegisterAsync(RegisterRequest item)
        {
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
            
            var newUser = new User
            {
                Id = Guid.NewGuid(),     
                CognitoSub = userSub,     

                Email = item.Email,
                FullName = item.FullName,

                Roleid = Guid.Parse("99999999-9999-9999-9999-999999999999")
            };

            await _userRepository.AddAsync(newUser);

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
