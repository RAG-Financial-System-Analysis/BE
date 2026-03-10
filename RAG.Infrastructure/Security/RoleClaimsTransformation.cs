using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
using RAG.Infrastructure.Database;
using System;
using System.Collections.Generic;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authentication;

using Microsoft.Extensions.Logging;

namespace RAG.Infrastructure.Security
{
    public class RoleClaimsTransformation : IClaimsTransformation
    {
        private readonly ApplicationDbContext _context;
        private readonly ILogger<RoleClaimsTransformation> _logger;

        public RoleClaimsTransformation(ApplicationDbContext context, ILogger<RoleClaimsTransformation> logger)
        {
            _context = context;
            _logger = logger;
        }

        public async Task<ClaimsPrincipal> TransformAsync(ClaimsPrincipal principal)
        {
            var identity = principal.Identity as ClaimsIdentity;
            if (identity == null || !identity.IsAuthenticated)
            {
                _logger.LogWarning("Identity is null or not authenticated.");
                return principal;
            }

            var subClaim = principal.FindFirst(ClaimTypes.NameIdentifier)
                           ?? principal.FindFirst("sub")
                           ?? principal.FindFirst("username")
                           ?? principal.FindFirst("client_id");

            if (subClaim == null) 
            {
                _logger.LogWarning("No sub claim found in token.");
                return principal;
            }

            var cognitoSub = subClaim.Value;
            _logger.LogInformation($"Found Cognito Sub: {cognitoSub}");

            var user = await _context.Users
                .AsNoTracking()
                .Include(u => u.Role)
                .Where(u => u.Cognitosub == cognitoSub)
                .Select(u => new { u.Id, RoleName = u.Role.Name })
                .FirstOrDefaultAsync();

            if (user != null)
            {
                _logger.LogInformation($"User found in DB. Role: {user.RoleName}");
                if (!string.IsNullOrEmpty(user.RoleName) && !principal.HasClaim(c => c.Type == ClaimTypes.Role))
                {
                    identity.AddClaim(new Claim(ClaimTypes.Role, user.RoleName));
                    _logger.LogInformation($"Added Role Claim: {user.RoleName}");
                }

                if (!principal.HasClaim(c => c.Type == "internal_user_id"))
                {
                    identity.AddClaim(new Claim("internal_user_id", user.Id.ToString()));
                    _logger.LogInformation($"Added internal_user_id claim: {user.Id}");
                }
            }
            else
            {
                _logger.LogWarning($"User with Cognito Sub {cognitoSub} not found in Database.");
            }
            
            return principal;
        }
    }
}
