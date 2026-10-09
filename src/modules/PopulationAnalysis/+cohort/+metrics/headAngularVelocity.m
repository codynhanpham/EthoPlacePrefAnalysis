function t = headAngularVelocity(standardizedTables, kvargs)
%%HEADANGULARVELOCITY Cohort summary of signed head angular velocity.
% Angular velocity is the wrapped time-derivative of the head bearing
% series, where head bearing is the direction from the ear midpoint (the
% rotation root) to the nose in the standardized coordinate system using
% the image convention (Y axis points down). Reported in deg/s: clockwise
% rotation is positive and counter-clockwise rotation is negative, falling
% out of the bearing convention (0 deg = up, +90 = right, -90 = left).
%
% Unlike the other head metrics, StimulusIncludesTrailingISI defaults to
% FALSE here, matching the Rust head-angle spans which exclude trailing ISI
% rows.

arguments
    standardizedTables struct {sdTable.mustBeStandardizedTable}
    kvargs.StimulusIncludesTrailingISI (1,1) logical = false
    kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}
end

t = cohort.metrics.utils.headMetricSummary(standardizedTables, kvargs, 'noseHeadingAngularVelocity');
end
