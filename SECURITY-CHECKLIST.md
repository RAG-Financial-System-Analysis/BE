# Security Checklist

Before committing to Git, ensure:

## ✅ Configuration Files
- [ ] `deployment-config.env` is in .gitignore
- [ ] `lambda-env.json` is in .gitignore  
- [ ] `appsettings.json` is in .gitignore
- [ ] Example files (*.example) are created and safe

## ✅ API Keys & Secrets
- [ ] No OpenAI API keys (sk-proj-*)
- [ ] No Gemini API keys (AIzaSy*)
- [ ] No AWS Access Keys (AKIA*)
- [ ] No AWS Secret Keys
- [ ] No database passwords

## ✅ Infrastructure Details
- [ ] No RDS endpoints
- [ ] No Cognito User Pool IDs
- [ ] No Cognito Client IDs
- [ ] No S3 bucket names with real data

## ✅ User Credentials
- [ ] No hardcoded passwords (Admin@123!!, Analyst@123!!)
- [ ] No real email addresses in examples

## ✅ Files to Check
- [ ] scripts/deployment-config.env → .gitignore
- [ ] lambda-env.json → .gitignore
- [ ] RAG.APIs/appsettings.json → .gitignore
- [ ] scripts/database/*.sh → cleaned or .gitignore
- [ ] scripts/tests/*.sh → cleaned
- [ ] All README.md files → cleaned

## ✅ Safe to Commit
- [ ] Only .example files with placeholders
- [ ] No sensitive data in any committed files
- [ ] .gitignore properly configured
