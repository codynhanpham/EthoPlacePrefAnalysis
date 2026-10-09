function [t, histogram] = headBearingAngle(standardizedTables, kvargs)
%%HEADBEARINGANGLE Cohort summary of head bearing angle statistics.
% Head bearing is the direction from the ear midpoint to the nose, in the
% standardized coordinate system using the image convention (Y axis points
% down). Reported in degrees over [-180, 180): 0 deg means facing directly
% up (12 o'clock), negative values mean facing left, positive values mean
% facing right, and +/-180 means facing down. This matches the companion
% Rust implementation's head_bearing_degrees.
%
% Statistics are circular: Mean is the circular mean and Std is the circular
% dispersion (sqrt(-2 ln R) in degrees). Min/Max are the raw linear extremes
% within the period (range endpoints). Last-First deltas use the wrapped
% difference of bout means.
%
% Unlike the other head metrics, StimulusIncludesTrailingISI defaults to
% FALSE here, matching the Rust head-angle spans which exclude trailing ISI
% rows.
%
% Optional second output: a histogram struct with fields 'bins' (72x1 frame
% counts, bin i covers [-180+5i, -175+5i) degrees), 'binEdges' (73x1 edges
% from -180 to 180), and 'total' (total valid frames). Not collected by
% cohort.summary(); opt-in for plotting via direct metric calls.

arguments
    standardizedTables struct {sdTable.mustBeStandardizedTable}
    kvargs.StimulusIncludesTrailingISI (1,1) logical = false
    kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}
end

[t, histogram] = cohort.metrics.utils.headMetricSummary(standardizedTables, kvargs, 'bearingAngle');
end
