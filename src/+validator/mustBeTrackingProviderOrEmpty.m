function mustBeTrackingProviderOrEmpty(val)
    if ~isempty(val) && ~isa(val, 'ui.trackingPlatforms.TrackingProvider')
        error('TrackingProvider must be an instance of ui.trackingPlatforms.TrackingProvider or empty.');
    end
end