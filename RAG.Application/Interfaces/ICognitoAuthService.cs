using RAG.Domain.DTOs.Auth;
using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Infrastructure.AWS.Interface
{
    public interface ICognitoAuthService
    {
        Task<string> RegisterAsync(RegisterRequest request);
        Task<AuthResponse> LoginAsync(LoginRequest request);
        Task<bool> VerifyEmailAsync(VerifyRequest request);
        Task<bool> LogoutAsync(string accessToken);
    }
}
