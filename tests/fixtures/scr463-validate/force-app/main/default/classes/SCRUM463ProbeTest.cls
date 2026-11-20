@isTest
public class SCRUM463ProbeTest {
    // House pattern (measured in SCRUM319OverdueOpportunityTest.cls): test methods carry
    // @isTest, not @Test — the org rejects "Annotation does not exist: Test".
    @isTest
    static void marker() {
        System.assertEquals(1, 1, 'one equals one');
    }
}
