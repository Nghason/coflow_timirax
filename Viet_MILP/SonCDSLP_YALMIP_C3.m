% clear;
% load"data_m10_c20";
%%
n_links    = fabric.numFabricPorts;     % nb of fabric ports (ingress+egress)    
n_machines = n_links/2;                 % nb of machines on the fabric
n_coflows  = length(coflows);           % nb of coflows
n_flows    = [coflows.numFlows];        % nb of flows of each coflow
n_flows_all = sum(n_flows);             % total nb of flows

portCapacity = [[fabric.machinesPorts.ingress] [fabric.machinesPorts.egress]];
portCapacity = [portCapacity.linkCapacity];
port_cumsum = [];
for i = 1:n_links 
    if i == 1
        port_cumsum(i) = 1;
    else if i == 2
        port_cumsum(i) = port_cumsum(i-1) -1 + n_flows_all;
    else 
        port_cumsum(i) = port_cumsum(i-1) + n_flows_all;
    end
    end
end
flows_cumsum = cumsum(n_flows);
time_instants = [0];
for c = coflows
   time_instants = [time_instants, c.deadline];
end
time_instants = unique(time_instants);
time_instants = sort(time_instants);
n_slots = length(time_instants) - 1; % n_coflows; % nb of time slots
time_slots = cell(1, n_slots); 
slot_duration = zeros(1, n_slots); 
for i = 1:n_slots
   time_slots{i} = [time_instants(i), time_instants(i+1)];
   slot_duration(i) = time_instants(i+1) - time_instants(i);
end

n_slots_of_coflow = zeros(1, n_coflows);

for c = coflows
	c.addParam.k_arrival = 1;    % all coflows arrive at t=0
    for i = 1:n_slots
        A = time_slots{i}(2);
        if c.deadline == time_slots{i}(2)
            c.addParam.k_deadline = i;
        end
    end
    n_slots_of_coflow(c.id) = c.addParam.k_deadline; 
    c.addParam.slot_id = (c.addParam.k_arrival:c.addParam.k_deadline); % slot indexes of coflow c
end
slot_duration_per_coflows = zeros(n_links * n_flows_all,n_slots);
zn = binvar(n_coflows,1);
send_rate = sdpvar(n_links * n_flows_all,n_slots);
cct_var = binvar(n_coflows,size(time_slots,2));

constraints = [ ];
for c = coflows
    cid = c.id;
    for f = c.flows
        fid = f.id;
        if cid ~= 1
            fid = fid + flows_cumsum(cid - 1);
        end
        for i = 1:n_slots_of_coflow(cid)% Chạy từng timeslot
            for j = 1:n_links % Chạy từng port
                if ismember(j,f.links) % Kiểm tra flow có thuộc port ko
                    if j == 1
                        slot_duration_per_coflows(fid,i) = slot_duration(i);
                    else
                        slot_duration_per_coflows(fid + port_cumsum(j),i) = slot_duration(i);
                    end
                end
            end
        end
    end
end
C1 = send_rate .* slot_duration_per_coflows;
%% Constraint 1: Accepted coflow will fully transmitt all of its data
count = 0;
for c = coflows % Kiểm tra từng coflow
    cid = c.id;
    for f = c.flows % Kiểm tra từng flow
        fid = f.id;
        if cid ~= 1 % Xác định flow id 
            fid = fid + flows_cumsum(cid - 1);
        end
        f_vol = f.volume;
        for i = 1:n_links % Kiểm tra từng port
            if ismember(i,f.links)  % Nếu port trùng với f.link của flow
                if i == 1
                   constraints = [constraints,zn(cid)*f_vol - sum(C1(fid, :)) == 0];
                else
                   constraints = [constraints,zn(cid)*f_vol - sum(C1(fid + port_cumsum(i), :)) == 0];                     
                end
%                 if count == 1
%                     constraints = [constraints,zn(cid)*f_vol - sum(C1(fid + port_cumsum(i), :)) == 0];
%                 end
%                 if count == 0
%                 if i == 1
%                     constraints = [constraints,zn(cid)*f_vol - sum(C1(fid, :)) == 0];
%                 else
%                     constraints = [constraints,zn(cid)*f_vol - sum(C1(fid + port_cumsum(i), :)) == 0];
%                 end
%                 count = count + 1;
%                 end
            end
        end
%        count = 0; % Sang flow mới set count = 0 
    end
end
%% C2
send_data_location = zeros(n_links * n_flows_all,n_slots);
for c = coflows
    cid = c.id;
    for f = c.flows
        fid = f.id;
        if cid ~= 1
            fid = fid + flows_cumsum(cid - 1);
        end
        for i = 1:n_slots_of_coflow(cid)
            for j = 1:n_links
                if ismember(j,f.links)
                    if j == 1
                        send_data_location(fid,i) = 1;
                    else
                        send_data_location(fid + port_cumsum(j),i) = 1;
                    end
                end
            end
        end
    end
end

C2 = send_rate .* send_data_location;
for p = 1:n_links
    for slot_id = 1:n_slots
        if p == 1 
            start_idx = port_cumsum(p);
            end_idx = port_cumsum(p + 1);
        else if p ==n_links
            start_idx = port_cumsum(p) + 1;
            end_idx = port_cumsum(p) + n_flows_all;
        else 
            start_idx = port_cumsum(p) + 1;
            end_idx = port_cumsum(p + 1);
        end
        end
        constraints = [constraints, sum(C2(start_idx:end_idx, slot_id)) <= portCapacity(p)];
    end
end
%% C3
%ma trận C3 sẽ chứa các giá trị send_rate theo thứ tự 
C3 = sdpvar;
count = 1;
for c = coflows % check cf
    cid = c.id;
    for f =c.flows % check each flow
        fid = f.id;
        if cid ~= 1
            fid = fid + flows_cumsum(cid - 1); % flow indx
        end
        for i = 1:n_links % check each port
            for j = 1:n_slots_of_coflow(1,cid) % check each timeslt of flow
            if ismember(i,f.links) % Nếu port trùng f.links
                if i == 1 % port 1
                    C3(count,j) = send_rate(fid,j);
                else % other port neead updated port index
                    C3(count,j) = send_rate(fid + port_cumsum(i),j);
                end
            end
            end
            if ismember(i,f.links)
                count = count + 1;
            end
        end
    end
end
%biến nhớ tạm cho phần xử lý
cache_mem_for_C3 = 0;
%biến Xj theo định dạng yalmip
C3_1 = sdpvar;
count = 1;
for c = coflows % coflow
    cid = c.id;
    c_vol = c.addParam.volumes(1,:);
    c_vol_value = sum(c_vol(:,:));
    c_vol_value = c_vol_value*2;
    if cid == 1     % Tạo index coflow 
        start_idx_C3 = 1;
        end_idx_C3 = n_flows(cid)*2 + start_idx_C3 - 1;
        cache_mem_for_C3 = end_idx_C3; 
    else
        start_idx_C3 =  cache_mem_for_C3 + 1;
        end_idx_C3 = n_flows(cid)*2 + start_idx_C3 - 1;
        cache_mem_for_C3 = end_idx_C3; 
    end
    for i = 1:1:n_slots % coflow/timeslot
        if i <= n_slots_of_coflow(cid)
        if i ==1    % Accumulate volume sum
            data_cumsum_var = sum(C3(start_idx_C3:end_idx_C3, i)) * slot_duration(1,i);
        else
            data_cumsum_var = data_cumsum_var + sum(C3(start_idx_C3:end_idx_C3, i)) * slot_duration(1,i);
        end
        % data/cf_data table per timeslot
         C3_1(count, i) = data_cumsum_var/c_vol_value; 
%          constraints = [constraints, data_cumsum_var/c_vol_value - cct_var(cid, i) >= 0];
        else
            C3_1(count, i) = 1 * zn(cid); % After fully transmitted, set others to 1
        end
    end
    count = count + 1;
end


%%
constraints = [constraints, send_rate >= 0];
constraints = [constraints, C2 >= 0];
constraints = [constraints, C1 >= 0];
ops = sdpsettings();
cct_var_for_obj = sdpvar;
for i = 1:n_coflows
    cct_var_for_obj(1,i) = sum(cct_var(i,:));
end
obj = -sum(zn(:,1))-(1/(n_links))*sum(cct_var_for_obj(:,1));
%obj = -sum(zn(:,1));
result = optimize(constraints,obj,ops);  
z_cct = value(cct_var);
z_Xj = value(C3_1);
% successfully solved
if result.problem == 0 
    z_sendrate = value(send_rate);
    % value(C1);
    %Value(C2);
    zn = value(zn);
    -value(obj) ;  
else
    disp('Wrong!');
end
