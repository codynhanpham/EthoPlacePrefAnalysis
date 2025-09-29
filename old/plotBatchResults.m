function plotBatchResults(resultsTable)

    if ~istable(resultsTable)
        try
            if isfile(resultsTable)
                % Load the results table
                resultsTable = load(resultsTable);
                resultsTable = resultsTable.resultsTable;
            else
                error("Input must be a table or a .mat file containing 'resultsTable'");
            end
        catch ME
            rethrow(ME);
        end
    end


    % Add an ALL column to the table with value of 'ALL' to group by all
    resultsTable = addvars(resultsTable, repmat("ALL", height(resultsTable), 1), 'NewVariableNames', "Genotype Group All", 'Before', "Genotype Group");
    resultsTable = convertvars(resultsTable, "Genotype Group All", "categorical");
    % Add a SEX column to the table with value of (split(Genotype Group, '|'){1}) to group by
    sexData = strings(height(resultsTable), 1);
    for i = 1:height(resultsTable)
        splitData = split(string(resultsTable{i, "Genotype Group"}), "|");
        if numel(splitData) >= 1
            sexData(i) = splitData{1};
        else
            sexData(i) = "Unknown";
        end
    end
    resultsTable = addvars(resultsTable, categorical(sexData), 'NewVariableNames', "Sex");
    resultsTable = convertvars(resultsTable, "Sex", "categorical");


    %% Create a normalized data columns (for each stim) that divides by total frame in "All Left Speaker" or "All Right Speaker"
    % Norm Matched Speakers
    normMatchedLeft = zeros(height(resultsTable), 1);
    normMatchedRight = zeros(height(resultsTable), 1);

    for i = 1:height(resultsTable)
        normMatchedLeft(i) = resultsTable{i, "Matched Left Speaker"} / resultsTable{i, "All Left Speaker"};
        normMatchedRight(i) = resultsTable{i, "Matched Right Speaker"} / resultsTable{i, "All Right Speaker"};
    end
    resultsTable = addvars(resultsTable, normMatchedLeft, normMatchedRight, 'NewVariableNames', ["Norm Matched Left Speaker", "Norm Matched Right Speaker"]);


    % For each row, use the value in "Matched Left Speaker" and find the other column that has the same value, Normalize that column by / "All Left Speaker"
    % Same for "Matched Right Speaker"
    for i = 1:height(resultsTable)
        matchedLeftValue = resultsTable{i, "Matched Left Speaker"};
        matchedRightValue = resultsTable{i, "Matched Right Speaker"};

        % Find the column name that has the same value as matchedLeftValue
        leftColName = "";
        rightColName = "";
        for j = 1:width(resultsTable)
            if isnumeric(resultsTable{i, j}) && resultsTable{i, j} == matchedLeftValue && resultsTable.Properties.VariableNames{j} ~= "Matched Left Speaker"
                leftColName = resultsTable.Properties.VariableNames{j};
            end
            if isnumeric(resultsTable{i, j}) && resultsTable{i, j} == matchedRightValue && resultsTable.Properties.VariableNames{j} ~= "Matched Right Speaker"
                rightColName = resultsTable.Properties.VariableNames{j};
            end
        end

        if ~isempty(leftColName) && leftColName ~= "All Left Speaker"
            normColName = strcat("Norm ", leftColName);
            if ~ismember(normColName, resultsTable.Properties.VariableNames)
                resultsTable = addvars(resultsTable, zeros(height(resultsTable), 1), 'NewVariableNames', normColName);
            end
            resultsTable{i, normColName} = matchedLeftValue / resultsTable{i, "All Left Speaker"};
        end

        if ~isempty(rightColName) && rightColName ~= "All Right Speaker"
            normColName = strcat("Norm ", rightColName);
            if ~ismember(normColName, resultsTable.Properties.VariableNames)
                resultsTable = addvars(resultsTable, zeros(height(resultsTable), 1), 'NewVariableNames', normColName);
            end
            resultsTable{i, normColName} = matchedRightValue / resultsTable{i, "All Right Speaker"};
        end
    end


    %% Speaker Prefs
    speakerPosStatsBySubjectCat = groupsummary(resultsTable, "Genotype Group All", ["mean","std"], ["Matched Left Speaker", "Matched Right Speaker"]);
    groups = string(speakerPosStatsBySubjectCat.("Genotype Group All")');
    groupN = string(speakerPosStatsBySubjectCat.("GroupCount")');
    meanLeft = speakerPosStatsBySubjectCat.("mean_Matched Left Speaker")';
    meanRight = speakerPosStatsBySubjectCat.("mean_Matched Right Speaker")';
    meanData = [meanLeft; meanRight];
    stdLeft = speakerPosStatsBySubjectCat.("std_Matched Left Speaker")';
    stdRight = speakerPosStatsBySubjectCat.("std_Matched Right Speaker")';
    stdData = [stdLeft; stdRight];

    % Join groups + groupN, matching elements
    groups = strcat(groups, " (n_trials = ", groupN, ")");
    plotGroupedBarFigure(meanData, stdData, groups, "Animal - Physical Speaker/Side Preferences", ["Left Speaker", "Right Speaker"]);

    speakerPosStatsBySubjectCat = groupsummary(resultsTable, "Sex", ["mean","std"], ["Norm Matched Left Speaker", "Norm Matched Right Speaker"]);
    groups = string(speakerPosStatsBySubjectCat.("Sex")');
    groupN = string(speakerPosStatsBySubjectCat.("GroupCount")');
    meanLeft = speakerPosStatsBySubjectCat.("mean_Norm Matched Left Speaker")';
    meanRight = speakerPosStatsBySubjectCat.("mean_Norm Matched Right Speaker")';
    meanData = [meanLeft; meanRight];
    stdLeft = speakerPosStatsBySubjectCat.("std_Norm Matched Left Speaker")';
    stdRight = speakerPosStatsBySubjectCat.("std_Norm Matched Right Speaker")';
    stdData = [stdLeft; stdRight];

    groups = strcat(groups, " (n_trials = ", groupN, ")");
    plotGroupedBarFigure(meanData, stdData, groups, "Animal - Physical Speaker/Side Preferences", ["Left Speaker", "Right Speaker"]);




    %% Stim Prefs
    
    % NORMAL - INVERTED
    % vbsInvertedIdx = resultsTable.("VBS Inverted") > 0;
    % vbsInverted = resultsTable(vbsInvertedIdx,:);
    % vbsInvertedStats = groupsummary(vbsInverted, "Genotype Group", ["mean","std"], ["Norm VBS Normal", "Norm VBS Inverted"]);
    % groups = string(vbsInvertedStats.("Genotype Group")');
    % groupN = string(vbsInvertedStats.("GroupCount")');
    % meanNormal = vbsInvertedStats.("mean_Norm VBS Normal")';
    % meanInverted = vbsInvertedStats.("mean_Norm VBS Inverted")';
    % meanData = [meanNormal; meanInverted];
    % stdNormal = vbsInvertedStats.("std_Norm VBS Normal")';
    % stdInverted = vbsInvertedStats.("std_Norm VBS Inverted")';
    % stdData = [stdNormal; stdInverted];

    % groups = strcat(groups, " (n_trials = ", groupN, ")");
    % plotGroupedBarFigure(meanData, stdData, groups, "Normal-Inverted Preferences", ["Normal Vocal Zone", "Inverted Vocal Zone"]);


    % NORMAL - SILENCE
    silenceIdx = resultsTable.("Silence (5s)") > 0;
    silence = resultsTable(silenceIdx,:);
    silenceStats = groupsummary(silence, "Sex", ["mean","std"], ["Norm VBS Normal", "Norm Silence (5s)"]);
    groups = string(silenceStats.("Sex")');
    groupN = string(silenceStats.("GroupCount")');
    meanNormal = silenceStats.("mean_Norm VBS Normal")';
    meanSilence = silenceStats.("mean_Norm Silence (5s)")';
    meanData = [meanNormal; meanSilence];
    stdNormal = silenceStats.("std_Norm VBS Normal")';
    stdSilence = silenceStats.("std_Norm Silence (5s)")';
    stdData = [stdNormal; stdSilence];

    groups = strcat(groups, " (n_trials = ", groupN, ")");
    plotGroupedBarFigure(meanData, stdData, groups, "Normal-Silence Preferences", ["Normal Vocal Zone", "Silence Zone"]);


    % NORMAL - PREDATOR
    predatorIdx = resultsTable.("Hawk Screeching") > 0;
    predator = resultsTable(predatorIdx,:);
    predatorStats = groupsummary(predator, "Sex", ["mean","std"], ["Norm VBS Normal", "Norm Hawk Screeching"]);
    groups = string(predatorStats.("Sex")');
    groupN = string(predatorStats.("GroupCount")');
    meanNormal = predatorStats.("mean_Norm VBS Normal")';
    meanPredator = predatorStats.("mean_Norm Hawk Screeching")';
    meanData = [meanNormal; meanPredator];
    stdNormal = predatorStats.("std_Norm VBS Normal")';
    stdPredator = predatorStats.("std_Norm Hawk Screeching")';
    stdData = [stdNormal; stdPredator];

    groups = strcat(groups, " (n_trials = ", groupN, ")");
    plotGroupedBarFigure(meanData, stdData, groups, "Normal-Predator Preferences", ["Normal Vocal Zone", "Hawk Screeching Zone"]);

    
    % NORMAL - WHITE NOISE
    whitenoiseIdx = resultsTable.("White Noise") > 0;
    whitenoise = resultsTable(whitenoiseIdx,:);
    whitenoiseStats = groupsummary(whitenoise, "Sex", ["mean","std"], ["Norm VBS Normal", "Norm White Noise"]);
    groups = string(whitenoiseStats.("Sex")');
    groupN = string(whitenoiseStats.("GroupCount")');
    meanNormal = whitenoiseStats.("mean_Norm VBS Normal")';
    meanWhitenoise = whitenoiseStats.("mean_Norm White Noise")';
    meanData = [meanNormal; meanWhitenoise];
    stdNormal = whitenoiseStats.("std_Norm VBS Normal")';
    stdWhitenoise = whitenoiseStats.("std_Norm White Noise")';
    stdData = [stdNormal; stdWhitenoise];

    groups = strcat(groups, " (n_trials = ", groupN, ")");
    plotGroupedBarFigure(meanData, stdData, groups, "Normal-White Noise Preferences", ["Normal Vocal Zone", "White Noise Zone"]);
end


function f = plotGroupedBarFigure(meanData, stdData, groups, titleStr, legendStr)
    f = figure("Name", titleStr, "Position", [300, 400, 1500, 500]);
    ax = axes(f);

    % Workaround to make sure bar() group the data correctly when meanData is square
    % Repeat the groups to match the number of columns in meanData
    % Weirdly enough, errorbar() seems to work correctly regardless, so no need to use meanDataT there
    if size(meanData,1) == size(meanData,2)
        groups = repmat(groups', 1, size(meanData,2));
        meanDataT = meanData';
    else
        meanDataT = meanData;
    end

    
    b = bar(ax, categorical(groups), meanDataT, "Interpreter", "none");
    % Plot error bars
    hold on;
    [ngroups,nbars] = size(meanData');
    x = nan(nbars, ngroups);
    for i = 1:nbars
        x(i,:) = b(i).XEndPoints;
    end
    errorbar(x, meanData, stdData,'k','linestyle','none');
    hold off;

    ax.YLabel.String = "% of Time Spent in Zone when Zone is Active";
    ax.TickLabelInterpreter = "none";
    ax.XLabel.Interpreter = "none";
    ax.Title.String = titleStr;
    legend(ax, legendStr, "Location", "northwest");
end