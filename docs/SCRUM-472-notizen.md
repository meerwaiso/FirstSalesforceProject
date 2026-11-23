# SCRUM-472 — Architect notizen (measured 2026-11-23)

- Survey base: origin/master @ 31eeee5 (git fetch origin first; shared checkout sat on feature/SCRUM-424 branch — never committed there).
- Branch: feature/SCRUM-472-company-size (worktree at cache/scratch/wt-472). Commits 0a4e30e + f6c8f67, author architect-agent (repo user.name is devops-agent -> used -c user.name).
- Reachability proof: git cat-file -e origin/feature/SCRUM-472-company-size:docs/SCRUM-472-design.md -> exit 0.
- House Picklist shape = <valueSet>/<valueSetDefinition> from Contact.Preferred_Contact_Method__c (deployed Prod 0Afg500000H3X7JCAV); NOT <picklist>/<picklistValues>.
- Lead standard fields with size words: Company, NumberOfEmployees, CompanyDunsNumber, DandbCompanyId (read from .sfdx/tools/soqlMetadata/standardObjects/Lead.json). PO said 'no employee field' — NumberOfEmployees exists; not repurposed.
- Lead PSs referencing Lead on master: 318, 378, 381 (Opportunity fields), 386, 394, 464_Fabrikant_List_Lead/Read (object Fabrikant__c), 467 (Opportunity). None carries objectPermissions on Lead.
- ListView column token for a custom Lead field: <columns>Lead.Last_Attempt_Date__c</columns> (measured in Nachfassliste.listView-meta.xml).
- Design doc committed BEFORE the Jira comment named it.
