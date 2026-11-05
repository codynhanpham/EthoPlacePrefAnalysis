classdef testGenotypeTokenUnification < matlab.unittest.TestCase
    % Mixed KO/Hom/Hem token tests: joinMetricTables must align rows whose
    % genotype tokens differ only by variant/case, and validateProtocolTables
    % must accept the same animal recorded with different tokens across two
    % protocol tables.

    methods (Test)
        function joinMetricTablesAlignsKoAndHomRows(testCase)
            % Two metric tables describing the SAME subjects, but table 2 uses
            % 'Hem' where table 1 uses 'KO' (Mecp2 male variant drift).
            t1 = makeMetricTable({'KO', 'WT'}, 'Distance During Stimulus (cm)');
            t2 = makeMetricTable({'Hem', 'WT'}, 'Speed Mean During Stimulus (cm/s)');
            t2.('Speed Mean During Stimulus (cm/s)') = [7; 8];

            tJoined = cohort.metrics.joinMetricTables({t1, t2});
            testCase.verifyEqual(height(tJoined), 2);
            % Canonical label wins: Mecp2 'KO'/'Hem' both resolve to 'Hem'
            testCase.verifyEqual(string(tJoined.('Genotype$')(1)), "Hem");
            % Metric columns from both tables aligned by subject
            testCase.verifyEqual(tJoined{:, 'Distance During Stimulus (cm)'}, [1; 2]);
            testCase.verifyEqual(tJoined{:, 'Speed Mean During Stimulus (cm/s)'}, [7; 8]);
        end

        function joinMetricTablesAlignsCaseOnlyDrift(testCase)
            % Undefined strain: case-only drift ('Mut' vs 'MUT') must still join
            % via the case-insensitive identity fallback (lowercased).
            t1 = makeMetricTable({'Mut', 'WT'}, 'Distance During Stimulus (cm)');
            t1.('Gene') = {'UndefinedStrain'; 'UndefinedStrain'};
            t2 = makeMetricTable({'MUT', 'WT'}, 'Speed Mean During Stimulus (cm/s)');
            t2.('Gene') = {'UndefinedStrain'; 'UndefinedStrain'};
            t2.('Speed Mean During Stimulus (cm/s)') = [7; 8];

            tJoined = cohort.metrics.joinMetricTables({t1, t2});
            testCase.verifyEqual(height(tJoined), 2);
            % Undefined strain: case-insensitive identity (lowercased)
            testCase.verifyEqual(string(tJoined.('Genotype$')(1)), "mut");
            testCase.verifyEqual(tJoined{:, 'Speed Mean During Stimulus (cm/s)'}, [7; 8]);
        end

        function validateProtocolTablesAcceptsCrossTokenSameAnimal(testCase)
            % Same animal (Mecp2 male) recorded as 'KO' in protocol table 1 and
            % 'Hem' in protocol table 2: subject keys must match after
            % canonicalization, so validation passes.
            md1 = struct('id', "M01", 'strain', "Mecp2", 'genotype', "KO", ...
                'sex', "Male", 'cagecode', "C1", 'dob', "", 'age', 10);
            md2 = struct('id', "M01", 'strain', "Mecp2", 'genotype', "Hem", ...
                'sex', "Male", 'cagecode', "C1", 'dob', "", 'age', 10);

            std1 = makeStdTable(md1);
            std2 = makeStdTable(md2);

            % Must NOT throw
            labels = cohort.internal.validateProtocolTables([std1, std2]);
            testCase.verifyEqual(numel(labels), 2);
        end

        function validateProtocolTablesStillRejectsDifferentAnimals(testCase)
            md1 = struct('id', "M01", 'strain', "Mecp2", 'genotype', "KO", ...
                'sex', "Male", 'cagecode', "C1", 'dob', "", 'age', 10);
            md2 = struct('id', "M02", 'strain', "Mecp2", 'genotype', "Hem", ...
                'sex', "Male", 'cagecode', "C1", 'dob', "", 'age', 10);

            std1 = makeStdTable(md1);
            std2 = makeStdTable(md2);

            testCase.verifyError(@() cohort.internal.validateProtocolTables([std1, std2]), ...
                'cohort:internal:validateProtocolTables:SubjectSetMismatch');
        end

        function subjectKeysFromTableCanonicalizesTokens(testCase)
            % Metric-table keys and animalMetadata keys must agree even when
            % the metric table carries the variant token. Gene_ID/Litter/Toe_ID
            % columns must carry the parseMouseId-derived values (same as
            % animalSubjectKey derives them from the id).
            md = struct('id', "M01", 'strain', "Mecp2", 'genotype', "KO", ...
                'sex', "m", 'cagecode', "C1", 'dob', "", 'age', 10);
            keyFromMeta = outlier.internal.animalSubjectKey(md);

            % Derive the same parseMouseId parts the metadata key used
            [geneId, litterId, mouseNumber] = cohort.metrics.utils.parseMouseId("M01", "Mecp2");

            T = table({'M01'}, {'Mecp2'}, {'C1'}, {geneId}, {'m'}, {'KO'}, {litterId}, {mouseNumber}, ...
                'VariableNames', {'Mouse_ID', 'Gene', 'Cage #', 'Gene_ID', 'Sex$', 'Genotype$', 'Litter', 'Toe_ID'});
            commonHeaders = {'Mouse_ID', 'Gene', 'Cage #', 'Gene_ID', 'Sex$', 'Genotype$', 'Litter', 'Toe_ID'};
            keysFromTable = outlier.internal.subjectKeysFromTable(T, commonHeaders);

            testCase.verifyEqual(keysFromTable{1}, keyFromMeta);
        end
    end
end


function t = makeMetricTable(genotypes, metricName)
    n = numel(genotypes);
    t = table( ...
        repmat({'M01'}, n, 1), ... % placeholder ids, replaced below
        repmat({'Mecp2'}, n, 1), ...
        repmat({'C1'}, n, 1), ...
        repmat({'Mecp2'}, n, 1), ...
        repmat({'Male'}, n, 1), ...
        genotypes(:), ...
        repmat({'L1'}, n, 1), ...
        (1:n)', ...
        repmat({'2020-01-01'}, n, 1), ...
        repmat({10}, n, 1), ...
        repmat({'ProtocolA'}, n, 1), ...
        (1:n)', ...
        'VariableNames', {'Mouse_ID', 'Gene', 'Cage #', 'Gene_ID', 'Sex$', ...
        'Genotype$', 'Litter', 'Toe_ID', 'DOB', 'Age', 'Stimulus Protocol', ...
        metricName});
    t.Mouse_ID = compose("M%02d", (1:n)');
end


function stdTable = makeStdTable(md)
    % Minimal standardizedTable-shaped struct satisfying sdTable.mustBeStandardizedTable
    % (required centerpoint columns + optional fps/px2cm/bodyparts fields).
    nRows = 10;
    stimNames = [repmat("NONE | Pre-Stimulus", 5, 1); repmat("SomeStim", 5, 1)];
    cp = table(linspace(-1, 1, nRows)', stimNames, rand(nRows, 1), rand(nRows, 1), rand(nRows, 1), rand(nRows, 1), ...
        'VariableNames', {'Trial time', 'Stimulus name', 'X center', 'Y center', ...
        'Distance from Midline', 'Arena Grid Score'});
    bp = table(linspace(-1, 1, nRows)', stimNames, ...
        'VariableNames', {'Trial time', 'Stimulus name'});
    animalMetadata = dictionary("k1", md);
    stdTable = struct('stimfileName', 'protocolA.flac', 'stimuliSorted', ["A", "B"], ...
        'animalMetadata', animalMetadata, 'centerpointData', cp, ...
        'fps', 30, 'px2cm', 0.1, 'bodyparts', bp);
end
