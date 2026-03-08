using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
using RAG.Infrastructure.Database;
using System;
using System.Collections.Generic;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Authentication;

namespace RAG.Infrastructure.Security
{
    public class RoleClaimsTransformation : IClaimsTransformation
    {
        private readonly ApplicationDbContext _context;

        public RoleClaimsTransformation(ApplicationDbContext context)
        {
            _context = context;
        }

        public async Task<ClaimsPrincipal> TransformAsync(ClaimsPrincipal principal)
        {
            var identity = principal.Identity as ClaimsIdentity;
            if (identity == null || !identity.IsAuthenticated)
            {
                return principal;
            }

            var subClaim = principal.FindFirst(ClaimTypes.NameIdentifier)
                           ?? principal.FindFirst("sub")
                           ?? principal.FindFirst("username");

            if (subClaim == null) return principal;

            var cognitoSub = subClaim.Value;

            var user = await _context.Users
                .AsNoTracking()
                .Include(u => u.Role)
                .Where(u => u.Cognitosub == cognitoSub)
                .Select(u => new { u.Id, RoleName = u.Role.Name })
                .FirstOrDefaultAsync();

            if (user != null)
            {
                if (!string.IsNullOrEmpty(user.RoleName) && !principal.HasClaim(c => c.Type == ClaimTypes.Role))
                {
                    identity.AddClaim(new Claim(ClaimTypes.Role, user.RoleName));
                }

                // Inject internal DB user Id so controllers can use it for FK references
                if (!principal.HasClaim(c => c.Type == "internal_user_id"))
                {
                    identity.AddClaim(new Claim("internal_user_id", user.Id.ToString()));
                }
            }
            return principal;
        }
    }
}
