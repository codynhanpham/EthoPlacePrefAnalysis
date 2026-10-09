function t = headSpeed(standardizedTables, kvargs)
%%HEADSPEED Cohort summary of ear-midpoint head speed statistics.
% Head position is the midpoint of the standardized Ear_left and Ear_right
% coordinates. Standardized bodypart coordinates are already in centimeters,
% so output speed is in cm/s. Missing ear tracking yields NaN metric values
% while preserving one metadata row per animal.

arguments
    standardizedTables struct {sdTable.mustBeStandardizedTable}
    kvargs.StimulusIncludesTrailingISI (1,1) logical = true
    kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}
end

t = cohort.metrics.utils.headMetricSummary(standardizedTables, kvargs, 'speed');
end
