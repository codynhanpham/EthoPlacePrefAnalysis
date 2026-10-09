function t = headAcceleration(standardizedTables, kvargs)
%%HEADACCELERATION Cohort summary of ear-midpoint acceleration statistics.
% Head position is the midpoint of the standardized Ear_left and Ear_right
% coordinates. Positive and negative derivatives are reported separately as
% acceleration and deceleration magnitudes in cm/s^2. Standardized bodypart
% coordinates are already in centimeters. Missing ear tracking yields NaN
% metric values while preserving one metadata row per animal.

arguments
    standardizedTables struct {sdTable.mustBeStandardizedTable}
    kvargs.StimulusIncludesTrailingISI (1,1) logical = true
    kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}
end

t = cohort.metrics.utils.headMetricSummary(standardizedTables, kvargs, 'acceleration');
end
