trigger LastRealContactDateTrigger on Task (after insert, after update, after delete) {
    Set<Id> affected = new Set<Id>();

    if (Trigger.isInsert) {
        for (Task t : Trigger.new) {
            if (t.Type == 'Call' && t.Status == 'Completed' && t.WhoId != null) {
                affected.add(t.WhoId);
            }
        }
    } else if (Trigger.isDelete) {
        for (Task t : Trigger.old) {
            if (t.Type == 'Call' && t.WhoId != null) {
                affected.add(t.WhoId);
            }
        }
    } else if (Trigger.isUpdate) {
        for (Integer i = 0; i < Trigger.new.size(); i++) {
            Task n = Trigger.new[i];
            Task o = Trigger.old[i];
            Boolean nCounted = (n.Type == 'Call' && n.Status == 'Completed' && n.WhoId != null);
            Boolean oCounted = (o.Type == 'Call' && o.Status == 'Completed' && o.WhoId != null);
            if (nCounted != oCounted || n.WhoId != o.WhoId || n.Type != o.Type) {
                if (n.WhoId != null) affected.add(n.WhoId);
                if (o.WhoId != null) affected.add(o.WhoId);
            }
        }
    }

    if (!affected.isEmpty()) {
        LastRealContactDateTrigger.recompute(affected);
    }
}
