%% GraspIt_hybrid_kdtree_LR_conf.m
%% 4/28/14
%  Builds a kdtree to partition up the input space, based on the given
%  binThreshold. For each node, a different logistic regression classifier
%  is trained. Test points are directed to the appropriate classifier to
%  make a prediction.
%  Like the previous confidence GP, this classifier has two training
%  stages: first the kdtree is built and all LR's are trained, then train2
%  points are given to them to make predictions on. This gives us an idea
%  of their confidence when predicting. If they aren't very
%  confident/accurate, refrain from predicting on any points in that area
%  during the test phase. This will increase precision of the classifier
%  overall.
%%
function GraspIt_hybrid_kdtree_LR_conf(energycutoff,binThreshold)

%me = mfilename;
me = sprintf('kd_LR_energy_%d_bin_%d',energycutoff,binThreshold);
use_timestamp = false;
thesisStartup;

% Hard-coded for printing convenience
metricNames = 'PointArng Extension Spread Limit PerpSym ParallelSym OrthoNorm Volume GraspIt_Volume GraspIt_Epsilon';

% Suppress pesky LR warnings
orig_warn_state = warning;
warning('off','all');

% Number of features to read
dimensionCount = 11;

%AUC Evaluation Parameters
cutoff = .8;        %Anything >= this value is classified as a success

%Data Storage
data = [];          %X parameters for GP Classifier
results1 = [];       %Y parameters for GP Classifier
results2 = [];      %Alternate Y parameter
groundtruth = [];

%---------------------------------------------------------------------------
%Data Conditions (Value of 1 turns on, value of 0 turns off unless specified)
%---------------------------------------------------------------------------

datastr = {};
results1str = {};
results2str = {};
res2index = [];


%Shake data collected Jan13
dzzf_human = 1;% <<<TURN ON HERE<<<<<
if dzzf_human > 0   
    datastr{end+1} = 'zhifei_human_data.csv';
end

dzzf_autograsp = 1;% <<<TURN ON HERE<<<<<
if dzzf_autograsp > 0   
    datastr{end+1} = 'zhifei_autograsp_data_sanitized.csv';
end
   
%------------End Defind Parameters-----------------------------------------

%%
%//////////////////////////////////////////////////////////////////////////
%-------------Seed Datasets------------------------------------
%//////////////////////////////////////////////////////////////////////////


for i = 1:length(datastr)
      datatemp = importdata(datastr{i});
      
      % For these datasets we only want the first 11 metrics
      data = [data;datatemp.data(:,1:dimensionCount)];
      % GraspIt estimate
      results1 = [results1;datatemp.data(:,dimensionCount+1)];
      % No crowdsourced data in the sets
      %results2 = ...
      % Physical testing
      groundtruth = [groundtruth;datatemp.data(:,dimensionCount+3)];
      if i ==1
          header = datatemp.colheaders(2:end);
      elseif i>1 && mean(strcmp(datatemp.colheaders(2:end),header))<1
         error('headers do not match, check data files')   
      end   
end

%------------End Seed Data-----------------------------------------

%%
%//////////////////////////////////////////////////////////////////////////
%-------------Condition Datasets------------------------------------
%//////////////////////////////////////////////////////////////////////////

%Remove NAN columns
datatemp = isnan(mean(data));
data(:,datatemp) = [];
disp('!!!!below quality measures have been removed due to insufficient data!!!!!!!!!!!!')
disp( header(datatemp))
header(datatemp) = [];

%%% We want to keep all dimensions so don't delete any
% %Figure out which QM's are significant with T-tests
% [p,keep,delete] = ttester(data,groundtruth,qmset,cutoff);
% disp('Keeping QMs:')
% disp('name        p values')
% for i = 1:length(keep)
%     disp([header(keep(i)) num2str(p(keep(i)),3)] )
% end
% 
% 
% %Delete non-important QM's
% disp('Deleting QMs:')
% disp('name        p values')
% for i = length(delete):-1:1
%     disp([header(delete(i)) num2str(p(delete(i)),3)] )
% end
% header(delete) = [];
% data(:,delete) = [];

data = sphereize(data);

% Run PCA on a copy for plotting the contour
finalDimensionNum = 2;
[~,data_pca,latent] = pca(data);

%Reduce components based on earlier specifications
data_pca = data_pca(:,logical([ones(1,finalDimensionNum) zeros(1,size(data,2)-finalDimensionNum)]));

% Testing only on physical testing successes
physicalCutoff = .8;

% Linear regression prediction must be >= this value to be positive
lrCutoff = .5;

%------------End condition Data-----------------------------------------
% ----- End copied code ----- %

loopn = 30;

% Data to use as testing set. If < 1, it is interpreted as
% a percentage; if >= 1, selects this many data points for the set.
testProportion = .33;
train2Proportion = .33;

summaryStats = [];

filter_with_confidence = 1;

% Number of nodes to record information for on each iteration
nodes_to_keep = 3;

% A node must meet this precision value to be colored in the contour map
contourPrecisionCutoff = .5;

% A bin needs at least this many points to be considered confident
support_threshold = 3;
disp(strcat('binThreshold:',num2str(binThreshold)));
disp(strcat('energy base:',num2str(energycutoff)));
disp(strcat('using confidence:',num2str(filter_with_confidence)));

if(~filter_with_confidence)
    confidence_thresholds = 0;
    binThreshold = size(data,1)+1;
else
    confidence_thresholds = .5:.1:.9;
end
% Subtract/add a small number to prevent minimum value being placed in
% bin_index 0 and maximum in 11.
PCA_min = min(data)-.0001;
PCA_max = max(data)+.0002;
for confidence_cutoff = confidence_thresholds
    predictions = {};
    trueValues = {};
    
    %auc = zeros(1,loopn);
    auc = [];
    rocx = [];
    rocy = [];
    
    % Passed to contour3d - added to each iteration
    mfout = [];
    mfout_precision = [];
    mfout_confidence = [];
    mfout_TP = [];
    indexout = [];
    indexout_precision = [];
    indexout_confidence = [];
    indexout_TP = [];
    
    for l = 1:loopn
        trainData = data;
        trainy = (results1 <= energycutoff);
        
        % Make testx vector of appropriate size
        if(train2Proportion >= 1)
            train2x = zeros(train2Proportion,1);
        else
            train2x = zeros(floor(size(trainData,1) * train2Proportion),1);
        end
        if(testProportion >= 1)
            testx = zeros(testProportion,1);
        else
            testx = zeros(floor(size(trainData,1) * testProportion),1);
        end

        
        train2Indices = randomIndices(trainData,length(train2x));
        testIndices = randomIndices(trainData,length(testx));
        % Unlike most of the other experiments, we want predictions for
        % both test and training points.
        testx = trainData(testIndices,:);
        train2x = trainData(train2Indices,:);
        trainData([testIndices; train2Indices],:) = [];
        trainy([testIndices; train2Indices]) = [];

        dbstop if error
        
        % Build kdtree
        tree = kdMedCreateTree(trainData,binThreshold);
        % Don't split on results, but include them for easy bin confidence
        % computing
        bins = kdGetAllBins(tree);
        fprintf('Number of bins: %d\n',size(bins,1));
        bin_size_sum = 0;
        for i = 1:size(bins,1)
            bin_size_sum = bin_size_sum + size(bins{i,1},1);
        end
        fprintf('Average bin size: %d\n',bin_size_sum / size(bins,1));
        
        % Train classifiers
        nodeIndices = kdGetAllNodeIndices(tree);
        
        % Store which bin each training point belongs in
        trainNodes = zeros(size(trainData,1),1);
        for i = 1:size(trainData,1)
            trainNodes(i) = kdGetBinIndex(tree,trainData(i,:));
        end
        train2Nodes = zeros(size(train2x,1),1);
        for i = 1:size(train2x,1)
            train2Nodes(i) = kdGetBinIndex(tree,train2x(i,:));
        end
        
        coefficients = cell(size(nodeIndices,1),1);
        % For every leaf in the tree:
        for i = 1:size(coefficients,1)
            % train a logistic regression classifier
            leafTrainingIndices = (trainNodes == nodeIndices(i));
            coefficients{i} = glmfit(trainData(leafTrainingIndices,:), [trainy(leafTrainingIndices) ones(sum(leafTrainingIndices),1)], 'binomial', 'link', 'logit');
        end
        
        % Predict on train2 set
        mf = zeros(size(train2x,1),1);
        for i = 1:size(train2x,1)
            idx = kdGetBinIndex(tree,train2x(i,:));
            B = coefficients{(nodeIndices==idx)};
            mf(i) = Logistic(B(1) + train2x(i,:) * B(2:end));
        end
        
        % For every index in nodeIndices:
        % compute the confidence rating by looking at ground truth
        % create logical vector of same size as nodeIndices, saying whether
        % or not to predict in bin.
        confidence = zeros(size(nodeIndices));
        actuals = groundtruth(train2Indices);
        for i = 1:size(nodeIndices,1)
            idx = nodeIndices(i);
            preds = mf(train2Nodes == idx);
            actuals_i = actuals(train2Nodes == idx);
            % conf = TP / (TP + FP)
            TP = sum(preds >= lrCutoff & actuals_i >= physicalCutoff);
            FP = sum(preds >= lrCutoff & actuals_i < physicalCutoff);
            confidence(i) = TP / (TP + FP);
        end

        % For every point in test set:
        % Find kdtree index
        % If confidence for the index is not high, remove from test set
        eliminate = false(size(testx,1),1);
        for i = 1:size(testx,1)
            idx = kdGetBinIndex(tree,testx(i,:));
            C = confidence(nodeIndices==idx);
            if(isnan(C) || C < confidence_cutoff)
                eliminate(i) = true;
            end
        end
        
        fprintf('Eliminated %d points\n',sum(eliminate));
        testIndices_final = testIndices(~eliminate);
        testx(eliminate,:) = [];
        
        if size(testx,1) < 10
            disp('Not enough valid test points; skipping iteration.');
            continue;
        end
        
        % For filtered test set:
        % Get LR predictions (this is mf) and ground truth
        mf = zeros(size(testx,1),1);
        % Keeps track of which predictions were from which nodes
        test_containing_nodes = zeros(size(testIndices,1),1);
        % We want these for all test indices including the eliminated ones
        for i = 1:size(test_containing_nodes,1)
            idx = kdGetBinIndex(tree,data(testIndices(i),:));
            test_containing_nodes(i) = idx;
        end
        test_containing_nodes_filtered = test_containing_nodes(~eliminate);
        
        % Classify the filtered points
        for i = 1:size(testx,1)
            idx = kdGetBinIndex(tree,testx(i,:));
            B = coefficients{(nodeIndices==idx)};
            mf(i) = Logistic(B(1) + testx(i,:) * B(2:end));
        end
       
        res = +(groundtruth(testIndices_final) >= cutoff);
        
        node_precisions = zeros(size(nodeIndices));
        % Generate the precision of all bins/nodes
        for i = 1:size(nodeIndices,1)
            [node_precisions(i), ~] = precisionAndRecall({mf(test_containing_nodes_filtered==nodeIndices(i)) >= lrCutoff},{res(test_containing_nodes_filtered==nodeIndices(i))},true);
        end
        mf_precision = zeros(size(test_containing_nodes,1),1);
        for i = 1:size(mf_precision)
            mf_precision(i) = node_precisions(nodeIndices==test_containing_nodes(i));
        end
        mf_TP = zeros(size(testIndices,1),1);
        for i = 1:size(mf_TP,1)
            if confidence(nodeIndices == test_containing_nodes(i)) >= confidence_cutoff
                test_idx = find(testIndices_final == testIndices(i));
                mf_TP(i) = mf(test_idx) >= lrCutoff && res(test_idx);
            else
                mf_TP(i) = 0;
            end
        end
                
        %% Dump high-precision nodes
        if sum(node_precisions >= .9) > nodes_to_keep
            bestNodes = [];
            colTitles = '';
            for i = 1:size(nodeIndices)
                if(isnan(node_precisions(i)) || node_precisions(i) < .9)
                    continue;
                end
                indicesInBin = testIndices_final(test_containing_nodes_filtered==nodeIndices(i));
                fprintf('Sample indices for node %d: %d, %d\n',nodeIndices(i),indicesInBin(1),indicesInBin(end));
                [tpn, fpn, tnn, fnn] = getTestResults(mf(test_containing_nodes_filtered==nodeIndices(i)) >= lrCutoff,res(test_containing_nodes_filtered==nodeIndices(i)) >= physicalCutoff);
                fprintf('  TP  /  FP  /  TN  /  FN  :\n  %d      %d      %d      %d\n\n',tpn,fpn,tnn,fnn);
                bestNodes = [bestNodes [size(indicesInBin,1); coefficients{i}(2:end); node_precisions(i)]];
                colTitles = sprintf('%s%d ',colTitles,nodeIndices(i));
            end
            printmat(bestNodes,'Best Nodes',sprintf('NodeSize %s Precision',metricNames),colTitles);
            
        else
            C = [-node_precisions nodeIndices];
            sortedNodes = sortrows(C);
            bestNodes = [];
            colTitles = '';
            for i = 1:nodes_to_keep
                indicesInBin = testIndices_final(test_containing_nodes_filtered==nodeIndices(i));
                if(size(indicesInBin,1) == 0)
                    continue;
                end
                fprintf('Sample indices for node %d: %d, %d\n',nodeIndices(i),indicesInBin(1),indicesInBin(end));
                [tpn, fpn, tnn, fnn] = getTestResults(mf(test_containing_nodes_filtered==nodeIndices(i)) >= lrCutoff,res(test_containing_nodes_filtered==nodeIndices(i)) >= physicalCutoff);
                fprintf('  TP  /  FP  /  TN  /  FN  :\n  %d      %d      %d      %d\n\n',tpn,fpn,tnn,fnn);
                bestNodes = [bestNodes [size(indicesInBin,1); coefficients{(nodeIndices==sortedNodes(i,2))}(2:end); -sortedNodes(i,1)]];
                colTitles = sprintf('%s%d ',colTitles,nodeIndices(i));
            end
            printmat(bestNodes,'Best Nodes',sprintf('NodeSize %s Precision',metricNames),colTitles);
        end
        %% End high-precision node dump
        
        mf_confidence = zeros(size(data,1),1);
        for i = 1:size(mf_confidence,1)
            mf_confidence(i) = confidence(kdGetBinIndex(tree,data(i,:)) == nodeIndices);
        end
                        
        %% Generate sample contours for confidence and precision
        if mod(l,10) == 0
            contour_file = strcat(savedir,'hybrid_contours\',sprintf('cntr_kd_LR_egy_%d_conf_%d_bin_%d_confidence_sample_%d',energycutoff,confidence_cutoff*10,binThreshold,l/10));
            generateCategorizedContour(data_pca,groundtruth,(1:size(data_pca,1))',mf_confidence,contour_file,sprintf('Bins with confidence >= %f',confidence_cutoff),confidence_cutoff,true);

            contour_file = strcat(savedir,'hybrid_contours\',sprintf('cntr_kd_LR_egy_%d_conf_%d_bin_%d_precision_sample_%d',energycutoff,confidence_cutoff*10,binThreshold,l/10));
            generateCategorizedContour(data_pca(testIndices,:),groundtruth(testIndices),(1:size(testIndices,1))',mf_precision,contour_file,sprintf('Bins with test precision >= %f',confidence_cutoff),.5:.1:.9,true);
            
            clearvars test_point_confidencesl contour_file;
        end
        %% End generate contour

        mfout = [mfout; mf];
        mfout_precision = [mfout_precision; mf_precision >= confidence_cutoff]; % Precision is mapped with multiple levels for sampling so do the binary cutoff here
        mfout_confidence = [mfout_confidence; mf_confidence >= confidence_cutoff];
        mfout_TP = [mfout_TP; mf_TP];
        indexout = [indexout; testIndices_final];
        indexout_precision = [indexout_precision; testIndices];
        indexout_confidence = [indexout_confidence; (1:size(data,1))']; % Confidence is given for all data points
        indexout_TP = [indexout_TP; testIndices];
        
        dbstop if error;
        
        % For every node:
        % Calculate precision and recall
        % Find nodes_to_keep highest-precision nodes
        % For each of these high-precision nodes:
            % Print datapoints from train2 set
            % Pick 1 or 2 pictures based on indices and save them
            % Print LR coefficients for the node
        
        
        %% Generate ROC curve
        try
            [perfx,perfy,perft,auc(end+1)] = perfcurve(res',normalizeer(mf)',1);
            %rocResults = [rocResults; [perfx perfy]];
            [rocx(:,end+1),rocy(:,end+1)] = rotandproject(perfx,perfy,.01);
        catch err
            auc(l) = NaN;
        end

        disp(strcat('Completed iteration: ',num2str(l)));
        [precision, recall] = precisionAndRecall({mf >= lrCutoff},{res},true);
        disp(strcat('Prediction points:',num2str(size(testIndices_final,1))));
        disp('  TP     FP     TN     FN');
        [tp, fp, tn, fn] = getTestResults(mf >= lrCutoff,res);
        disp([tp, fp, tn, fn]);
        disp('Precision / Recall');
        disp([precision recall]);
        predictions{l} = (mf >= lrCutoff);
        trueValues{l} = res;
    end
    
    [ave,uppererr,lowererr,upperstd,lowerstd,kstat,kstatsterr,kstatstd] = rotandextrap(rocx,rocy,size(auc,1));
    
    if(filter_with_confidence)
        contour_file = strcat(savedir,'hybrid_contours\',sprintf('cntr_kd_LR_egy_%d_conf_%d_bin_%d',energycutoff,confidence_cutoff*10,binThreshold));
        contour_file_TP = strcat(savedir,'hybrid_contours\',sprintf('cntr_kd_LR_TP_egy_%d_conf_%d_bin_%d',energycutoff,confidence_cutoff*10,binThreshold));
        contour_file_precision = strcat(savedir,'hybrid_contours\',sprintf('cntr_kd_LR_precision_egy_%d_conf_%d_bin_%d',energycutoff,confidence_cutoff*10,binThreshold));
    else
        contour_file = strcat(savedir,'hybrid_contours\',sprintf('cntr_kd_LR_egy_%d_nofilter',energycutoff));
        contour_file_TP = strcat(savedir,'hybrid_contours\',sprintf('cntr_kd_LR_TP_egy_%d_nofilter',energycutoff));
        contour_file_precision = strcat(savedir,'hybrid_contours\',sprintf('cntr_kd_LR_precision_egy_%d_nofilter',energycutoff));
    end
    generateCategorizedContour(data_pca,groundtruth,indexout_confidence,mfout_confidence,contour_file,sprintf('Points with high average confidence\nconfidence=%f',confidence_cutoff),[.5 .75 .9]);
    generateCategorizedContour(data_pca,groundtruth,indexout_TP,mfout_TP,contour_file_TP,sprintf('Areas of frequent true positives\nconfidence=%f',confidence_cutoff),[.5 .75 .9]);
    generateCategorizedContour(data_pca,groundtruth,indexout_precision,mfout_precision,contour_file_precision,sprintf('Areas of high average precision\nconfidence=%f',confidence_cutoff),[.5 .75 .9]);
    
    
    %% Generate AUC curve
%     fig = figure;
%     set(fig, 'units', 'inches', 'pos', [8 5 3.25 3])
%     set(gca,'FontSize',10)
%     fill(([uppererr(:,1)' rot90(lowererr(:,1),2)'].*100),([uppererr(:,2)' rot90(lowererr(:,2),2)'].*100),[.75 .75 .75])
%     %fill(([uppererr(:,1)' rot90(lowererr(:,1),2)'].*100),([uppererr(:,2)' rot90(lowererr(:,2),2)'].*100),[.75 .75 .75])
%     hold on
%     plot(ave(:,1).*100,ave(:,2).*100,'k','linewidth',2)
%     %plot(rocResults(:,1).*100,rocResults(:,2).*100,'k','linewidth',2)
%     plot([0 100],[0 100],'color',[.5 .5 .5])
%     set(gca,'box','on','position',[.17,.15,.78,.8])
%     axis square
%     axis([0 100 0 100])
%     ylabel({'TPR';'(%)'})
%     xlabel('FPR (%)')
%     set(get(gca,'YLabel'),'Rotation',0)
%     plot([40 45],[52,60],'k','linewidth',1)
%     set(get(gca,'YLabel'),'Position',[-13 45. 1.001])
%     text(10,84,'GP with PC1','FontSize',10)
%     text(10,8,'Random Guess','FontSize',10)
    %%

    disp('Overall results (hybrid)');
    if(filter_with_confidence)
        disp(strcat('Confidence threshold=',num2str(confidence_cutoff)));
    end
    if(~filter_with_confidence)
        disp('All datapoints used');
    else
        disp('Filtered datapoints');
    end
    
    %Display AUC Info
    disp('AUC ave err std')
    disp(mean(auc))
    disp(std(auc)/(size(auc,1))^.5)
    disp(std(auc))
    
    [precision_macro, recall_macro] = precisionAndRecall(predictions,trueValues,true);
    disp('Precision / Recall macro');
    disp([precision_macro recall_macro]);
    disp('');
    [precision_micro, recall_micro] = precisionAndRecall(predictions,trueValues,false);
    disp('Precision / Recall micro');
    disp([precision_micro recall_micro]);

end

% disp('    TPR       FPR       TNR       FNR       cutoff');
% disp(summaryStats);

warning(orig_warn_state);

thesisCleanup;
end
