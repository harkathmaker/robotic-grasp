clc

%%%BEGIN COPY ---SETUP WORK FOR GPML---
disp(['executing gpml startup script...']);

OCT = exist('OCTAVE_VERSION') ~= 0;           % check if we run Matlab or Octave

me = mfilename;                                            % what is my filename
mydir = which(me); mydir = mydir(1:end-2-numel(me));        % where am I located
if OCT && numel(mydir)==2 
  if strcmp(mydir,'./'), mydir = [pwd,mydir(2:end)]; end
end                 % OCTAVE 3.0.x relative, MATLAB and newer have absolute path

addpath(mydir(1:end-1))
addpath([mydir,'cov'])
addpath([mydir,'doc'])
addpath([mydir,'inf'])
addpath([mydir,'lik'])
addpath([mydir,'mean'])
addpath([mydir,'util'])
addpath([mydir,'Mechanical Turk Data'])  %HAS ROC FUNCTION BUILT IN

clear me mydir
%%%%%END COPY


clear all, close all


%---Define parameters----
leave = 20;  %leaves out desired number in %
cutoff = .8;

%PULL IN IROS DATA EARLY FOR PROCESSING
shakeresults = xlsread('IROS_RESULTSp2.xls');
averesults = shakeresults;
shakedata = xlsread('IROS_DATA2p2.xls');
%shakedata = xlsread('IROS_DATA.xls');
results = bincutoff(averesults,.8);
energy = shakedata(:,6);

targetedbins = xlsread('top20bin.xls');

datacondition = 2;  %Select which dataset you want

%Select dataset
if datacondition ==1
    %Physical shake testing only
    [results, index, data] = dataprep(shakedata, shakeresults, 8);
    savestr = '2013shakeonly';
elseif datacondition ==2
    %Mechanical turk only
    mturresults = xlsread('mechturkrawdata.xls');
    data = mturresults(:,9);
    index = mturresults(:,1);
    dataindex = sort(unique(mturresults(:,1)));
    data = matave([index data]);
    data(:,1) = [];
end

data = normalizeer(data);
energy = normalizeer(energy);
leave = 20;

x = [];
y = x;
enerx = x;
enery = x;
index = (1:72)';

for i = 1:300;
   [ trainx, trainy,~, ~, ~, ~, ~] = leaverand2( data,results,index,leave);
   [ trainxener, trainyener,~, ~, ~, ~, ~] = leaverand2( energy,results,index,leave);
   
   trainx = normalizeer(trainx);
   trainxener = normalizeer(trainxener);
   
   try
       [temp1x,temp1y] = perfcurve(trainy',trainx','1');
       x = [x temp1x];
       y = [y temp1y];       
   end
   
   try
       [temp2x,temp2y] = perfcurve(trainyener',trainxener','1'); 
       enerx = [enerx temp2x];
       enery = [enery temp2y];
   end
end

[ave,upper,lower,kstat,kstatsterr] = rotandextrap(x,y);
[aveener,upperener,lowerener,kstatener,kstatsterrener] = rotandextrap(enerx,enery);

[xraw,yraw,~,auc] = perfcurve(results',data','1');
[enerxraw,eneryraw,~,enerauc] = perfcurve(results',energy','1');

% figure (1)
% plot(xraw.*100,yraw.*100)
% hold on
% axis square
% plot([0 100],[0 100],'color',[.5 .5 .5])
% plot(enerxraw*100,eneryraw*100,'k')
% legend('mtur','energy','random guess',-4)
% ylabel({'TPR';'(%)'})
% %text(-25,47,'(Percent)','FontSize',10)
% xlabel('FPR (%)')

hold off

disp(auc)
disp(enerauc)
load gp9jul



% close all
figure(2)
% set(figure(1), 'units', 'inches', 'pos', [8 5 3.25 3])
% set(gca,'FontSize',10)
fill(([gpupper(:,1)' rot90(gplower(:,1),2)'].*100),([gpupper(:,2)' rot90(gplower(:,2),2)'].*100),[.8 .8 .8])
hold on
fill(([upperener(:,1)' rot90(lowerener(:,1),2)'].*100),([upperener(:,2)' rot90(lowerener(:,2),2)'].*100),[.55 .55 .55])



fill(([upper(:,1)' rot90(lower(:,1),2)'].*100),([upper(:,2)' rot90(lower(:,2),2)'].*100),[.25 .25 .25])


plot(aveener(:,1).*100,aveener(:,2).*100,'k')
plot(ave(:,1).*100,ave(:,2).*100,'k','linewidth',2)
plot(gpave(:,1).*100,gpave(:,2).*100,'k','linewidth',2)
%plot(rocenerx,rocenery,'--','color',[.25 .25 .25])
plot([0 100],[0 100],'color',[.5 .5 .5])
set(gca,'box','on','position',[.17,.15,.78,.8])
axis square
axis([0 100 0 100])
ylabel({'TPR';'(%)'})
%text(-25,47,'(Percent)','FontSize',10)
xlabel('FPR (%)')
% set(get(gca,'YLabel'),'Rotation',0)
% plot([40 45],[52,60],'k','linewidth',1)
% set(get(gca,'YLabel'),'Position',[-13 45. 1.001])
text(30,50,'Energy','FontSize',10)
text(10,84,'GP with PC1','FontSize',10)
text(10,8,'Random Guess','FontSize',10)
text(10,8,'Mturk','FontSize',10)
% plot(ave(kstat,1),ave(kstat,2),'kx')




% for i = 1:300
%     plot(rocenergx(:,i),rocenergy(:,i))
%     hold on
% end

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %OUTPUTS
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% disp('\nGP generated FP Rate: ')
% disp(fitnorm(statnorm,1))
% 
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %ROC GRAPHs
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% %Plot Setup 21Mar13
% hold on
% %Raw Data and fit curves
% plot(ccritnorm(:,6),ccritnorm(:,7),':k','LineWidth',1)
% plot(fitnorm(:,1),fitnorm(:,2),'k','LineWidth',3)
% %Random Gueass Line
% plot([0 1],[0 1],'color',[.2 .2 .2])
% legend('GP raw', 'GP Fitted Curve','Random Guess',4)
% hold off
% xlabel('False Positive Rate')
% ylabel('True Positive Rate')
% title('ROC Space Normalized Grasp Data')
% axis([0 1 0 1])
% axis square
% 
% save(savestr);