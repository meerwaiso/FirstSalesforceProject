/**
 * [SCRUM-483] Tier 3 of ADR-4: the ownership move AND its compensation were both
 * refused. The trail row still says Failed (AC11: shown, not hidden), and the
 * caller is told with a NAMED exception so a half-moved state cannot be silently
 * ignored. Its own source file — the Apex compiler rejects a second top-level
 * class in one file (measured: "Missing '<EOF>' at 'class'").
 *
 * @author developer-agent
 * @date 2026-11-27
 */
public class SalesDepartureHandoverException extends Exception {
}
