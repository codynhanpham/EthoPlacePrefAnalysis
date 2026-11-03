function [fig, data] = fingerprintRadarEverything(fp, kvargs)
    %%FINGERPRINTRADAREVERYTHING High-resolution fingerprint radar: one spoke per metric context.
    %
    %   fig = graphics.fingerprintRadarEverything(fp)
    %   [fig, data] = graphics.fingerprintRadarEverything(fp, ...)
    %
    %   Thin variant of graphics.fingerprintRadar with SpokeLevel = "context":
    %   instead of aggregating contexts into metric families, every whitelisted
    %   metric context gets its own spoke (more spokes == higher resolution
    %   circle), in the same canonical tier -> protocol -> stimulus ->
    %   family -> metric order. Purely for visualization: always no grid, no
    %   markers, and no spoke labels; the black + marks the plot center and
    %   the title carries the strain. Effect computation, units, clamps and
    %   the second-output table are identical to fingerprintRadar - see its
    %   documentation for the line definitions (genotype effect, sex effect,
    %   genotype x sex interaction) and the option semantics below.
    %
    %   Named options (as in fingerprintRadar):
    %       ClampZ | ClampDelta          display clamp per radial unit
    %       RadialUnit                   "z" (default) or "cliffsDelta"
    %       StatsTable | PerAnimalLong   required inputs for delta mode
    %       InteractionThreshold         NaN = auto per unit
    %       Smooth | PointsPerSpoke      closed-curve smoothing
    %
    %   See also: graphics.fingerprintRadar, cohort.internal.cliffsDelta, spider_plot

    arguments
        fp struct
        kvargs.ClampZ (1,1) double {mustBePositive, mustBeFinite} = 3
        kvargs.ClampDelta (1,1) double {mustBePositive, mustBeFinite} = 1
        kvargs.RadialUnit (1,1) string = "z"
        kvargs.StatsTable table = table()
        kvargs.PerAnimalLong table = table()
        kvargs.InteractionThreshold (1,1) double = NaN
        kvargs.Smooth (1,1) logical = true
        kvargs.PointsPerSpoke (1,1) double {mustBePositive, mustBeInteger} = 24
    end

    [fig, data] = graphics.fingerprintRadar(fp, ...
        ClampZ=kvargs.ClampZ, ...
        ClampDelta=kvargs.ClampDelta, ...
        RadialUnit=kvargs.RadialUnit, ...
        StatsTable=kvargs.StatsTable, ...
        PerAnimalLong=kvargs.PerAnimalLong, ...
        InteractionThreshold=kvargs.InteractionThreshold, ...
        Smooth=kvargs.Smooth, ...
        PointsPerSpoke=kvargs.PointsPerSpoke, ...
        SpokeLevel="context", ...
        ShowGrid=false, ...
        ShowMarkers=false);
end
