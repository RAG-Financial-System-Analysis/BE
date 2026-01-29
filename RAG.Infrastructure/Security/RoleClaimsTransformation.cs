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

            var userRole = await _context.Users
                .AsNoTracking()
                .Include(u => u.Role) 
                .Where(u => u.CognitoSub == cognitoSub)
                .Select(u => u.Role.Name) 
                .FirstOrDefaultAsync();
            if (!string.IsNullOrEmpty(userRole))
            {
                if (!principal.HasClaim(c => c.Type == ClaimTypes.Role))
                {
                    identity.AddClaim(new Claim(ClaimTypes.Role, userRole));
                }
            }
            return principal;
        }
    }
}
