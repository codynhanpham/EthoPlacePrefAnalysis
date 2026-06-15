function f = dtwByBoutBinned(standardizedTable, compareGroups, kvargs)
    %%DTWBYBOUTBINNED Compute the Dynamic Time Warping (DTW) distance across compareGroups, split by bout binned

        arguments
        standardizedTable struct {mustBeNonempty}
        compareGroups (1,:) cell {mustBeNonempty, mustBeText}

        kvargs.BinWidth (1,1) {mustBePositive, mustBeInteger} = 1 % number of bouts per bin
        kvargs.Title {validator.mustBeTextScalarOrEmpty} = ''
        kvargs.SameYLim (1,1) logical = true % whether to harmonize y-limits across all subplots for direct comparability
    end





end


