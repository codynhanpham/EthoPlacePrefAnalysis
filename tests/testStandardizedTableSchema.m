classdef testStandardizedTableSchema < matlab.unittest.TestCase
    methods (Test)
        function validatesNewSchema(testCase)
            standardizedTable = makeStandardizedTable(3, 2, 1, 10);
            testCase.verifyWarningFree(@() sdTable.mustBeStandardizedTable(standardizedTable));
            testCase.verifyTrue(istable(standardizedTable.bodyparts));
            testCase.verifyEqual(standardizedTable.fps, 10);
            testCase.verifyEqual(standardizedTable.px2cm, 0.5);
        end

        function filtersBodypartColumnsWithMetadata(testCase)
            standardizedTable = makeStandardizedTable(3, 2, 1, 10);
            filtered = sdTable.subsetByMetadata(standardizedTable, Sex={'F'});
            testCase.verifySize(filtered.centerpointData.('X center'), [3, 1]);
            testCase.verifySize(filtered.bodyparts.('X nose'), [3, 1]);
            testCase.verifyEqual(numel(keys(filtered.animalMetadata)), 1);
        end

        function filtersBodypartRowsWithStimulusBlock(testCase)
            standardizedTable = makeStandardizedTable(4, 2, 1, 10);
            filtered = sdTable.subsetByStimBlock(standardizedTable, 'stimulus');
            testCase.verifyEqual(height(filtered.centerpointData), 2);
            testCase.verifyEqual(height(filtered.bodyparts), 2);
            testCase.verifyEqual(filtered.bodyparts.('X nose'), [12, 12; 13, 13]);
        end

        function joinsBodypartsAndPreservesGroupOrder(testCase)
            tableA = makeStandardizedTable(3, 1, 1, 10, "A");
            tableB = makeStandardizedTable(4, 1, 2, 10, "B");
            tableA.stimfileName = "A.flac";
            tableB.stimfileName = "B.flac";
            [joined, nAnimalsA] = population.temp.joinStdTableByStim(...
                tableA, tableB, 'EmbeddedNAnimalA', true);

            testCase.verifyEqual(nAnimalsA, 1);
            testCase.verifyEqual(joined.nAnimalsA, 1);
            testCase.verifyTrue(istable(joined.bodyparts));
            testCase.verifySize(joined.centerpointData.('X center'), [4, 2]);
            testCase.verifySize(joined.bodyparts.('X nose'), [4, 2]);
            testCase.verifyEqual(joined.bodyparts.('X nose')(1, 1), 11);
            testCase.verifyEqual(joined.bodyparts.('X nose')(1, 2), 12);
        end

        function rejectsIncompatibleConversionFactors(testCase)
            tableA = makeStandardizedTable(3, 1, 1, 10);
            tableB = makeStandardizedTable(3, 1, 2, 10);
            tableB.px2cm = 0.25;
            testCase.verifyError(@() population.temp.joinStdTableByStim(tableA, tableB), ...
                'population:temp:joinStdTableByStim:Px2cmMismatch');
        end

        function joinsWhenOptionalFieldsAreAbsentFromBothInputs(testCase)
            tableA = rmfield(makeStandardizedTable(3, 1, 1, 10, "A"), ...
                {'fps', 'px2cm', 'bodyparts'});
            tableB = rmfield(makeStandardizedTable(4, 1, 2, 10, "B"), ...
                {'fps', 'px2cm', 'bodyparts'});

            joined = population.temp.joinStdTableByStim(tableA, tableB);

            testCase.verifySize(joined.centerpointData.('X center'), [4, 2]);
            testCase.verifyFalse(isfield(joined, 'fps'));
            testCase.verifyFalse(isfield(joined, 'px2cm'));
            testCase.verifyFalse(isfield(joined, 'bodyparts'));
        end

        function rejectsOneSidedOptionalFields(testCase)
            fieldNames = {'fps', 'px2cm', 'bodyparts'};
            for fieldIndex = 1:numel(fieldNames)
                tableA = makeStandardizedTable(3, 1, 1, 10);
                tableB = makeStandardizedTable(3, 1, 2, 10);
                tableB = rmfield(tableB, fieldNames{fieldIndex});

                testCase.verifyError(...
                    @() population.temp.joinStdTableByStim(tableA, tableB), ...
                    'population:temp:joinStdTableByStim:OptionalFieldPresenceMismatch');
            end
        end
    end
end

function standardizedTable = makeStandardizedTable(nRows, nAnimals, valueOffset, fps, keyPrefix)
    if nargin < 5
        keyPrefix = "animal";
    end
    trialTime = (0:nRows-1)' / fps;
    stimulusName = repmat("Stimulus", nRows, 1);
    stimulusName(1) = "NONE | Pre-Stimulus";
    stimulusName(end) = "NONE | Post-Stimulus";

    centerpointData = table(trialTime, stimulusName, ...
        repmat((1:nRows)', 1, nAnimals) + valueOffset, ...
        repmat((1:nRows)', 1, nAnimals) + valueOffset, ...
        repmat((1:nRows)', 1, nAnimals), ...
        repmat((1:nRows)', 1, nAnimals), ...
        'VariableNames', {'Trial time', 'Stimulus name', 'X center', ...
        'Y center', 'Distance from Midline', 'Arena Grid Score'});
    bodyparts = table(trialTime, stimulusName, ...
        repmat((10:10+nRows-1)', 1, nAnimals) + valueOffset, ...
        repmat((20:20+nRows-1)', 1, nAnimals) + valueOffset, ...
        'VariableNames', {'Trial time', 'Stimulus name', 'X nose', 'Y nose'});

    metadata = configureDictionary("string", "struct");
    for animalIndex = 1:nAnimals
        if animalIndex == 1
            sex = "F";
        else
            sex = "M";
        end
        metadata(keyPrefix + animalIndex) = struct(...
            'sex', sex, 'strain', "strain", 'genotype', "genotype");
    end

    standardizedTable = struct(...
        'stimfileName', "stimulus.flac", ...
        'stimuliSorted', ["A", "B"], ...
        'animalMetadata', metadata, ...
        'fps', fps, ...
        'px2cm', 0.5, ...
        'centerpointData', centerpointData, ...
        'bodyparts', bodyparts);
end
