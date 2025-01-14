REF: https://github.com/WangXuan95/FPGA-DDR-SDRAM?tab=readme-ov-file#cn.

控制器用户侧接口：AXI4 + 维测接口（APB） + SIDEBIND（边带信号）

考虑到是否支持严格保序，控制器分为逻辑层和物理层。
    -严格保序的逻辑层：
        -控制器在接收用户命令时，按照提交顺序排队
        -当检测到命令间存在依赖时，会强制严格按顺序执行。
    -灵活的物理层优化：
        -在确保数据一致性的前提下，控制器会在底层对命令进行重排序、并行化或合并
        -例如：
            -优先执行同一Bank上的命令以减少切换延迟
            -将读取和写入分组处理以提高突发性能

需要一个命令解析单元，对axi4命令进行解析；

需要一个命令分发单元，对解析后的命令进行分发，分发方式可以是按照bank分发到不同队列。
    -Bank间调度
        -轮询优先（Round-Robin）
            -依次轮询各Bank队列，确保公平性。
        -优先级调度
            -可以为某些Bank设置更高优先级
        -动态负载平衡
            -优先处理命令较少的Bank队列，避免某些队列过载
    -Bank内调度
        -行命令优先（Row Buffer Hit First）
            -优先执行命中当前行缓冲的命令，减少行切换的开销（如减少tRP和tRAS延迟）
        -预充电优化（Precharge Optimization）
            -如果后续命令访问同一行，可以延迟或跳过PRECHARGE命令
    -Refresh调度
        -刷新操作（REFRESH）会组织同一Bank的操作：
            -确保在刷新周期到来之前尽可能多地完成队列中的命令
            -在刷新期间，优先调度其他Bank的队列
    -同Bank命令冲突处理：
        -如果同一Bank的多个命令访问不同行，可能引发冲突
        -解决办法：将冲突命令延迟或重新排序。

解决跨Bank保序的设计方案
方案1：全局命令队列
    -在命令分发到各Bank之前，所有命令保存在一个全局队列中，并按用户提交的顺序进行解析。
    -实现逻辑：
        -1.对全局命令队列中的命令依次解析。
        -2.检查每条命令的依赖性
            -如果某条命令与前面命令无冲突，立即分发到对应Bank队列。
            -如果有冲突，等待依赖满足后再分发
        -3.在执行前，确保命令按照提交顺序完成。

写后读一致性：
    -如果用户在一次写操作后立即发起读操作，控制器需要保证读操作的数据来自写后的数值，而不是DDR介质中未刷新的旧值。

命令执行重排序的意义：
    -保序执行通常实现简单，但可能导致性能底下；非严格保序需要更复杂的硬件逻辑（如命令队列、调度器、依赖检查器）
    -DDR时序（如tRP、tRAS）限制会影响命令的执行顺序，控制器需要综合考虑时序和性能。

命令调度重排序与公平性冲突

地址映射与管理：
    -用户接口通常提供逻辑地址，而具体的DDR地址（Bank、Row、Colomn）由控制器内部解析。
        -抽象地址：用户看到的是一个平坦的地址空间
        -地址映射：控制器负责将抽象地址映射到实际的DDR物理地址（Bank/Row/Colomn）

用户侧开放命令：
    读（READ）
        -功能：
            -从指定地址读取数据
        -接口要求：
            -提供目标内存地址或地址范围
            -返回数据有效信号和数据
        -实现：
            -控制器内部会根据地址解析对应的Bank、Row和Colomn，然后发送底层DDR命令（如ACTIVATE、READ等）
            -用户无需感知这些细节
    写（WRITE）
        -功能：
            -向指定地址写入数据
        -接口要求：
            -提供目标内存、数据和写入有效信号。
        -实现：
            -控制器会自动管理底层操作（如ACTIVATE、WRITE、RECHARGE等），完成数据写入
    突发读写（Burst Read/Write）
        -功能：
            -一次性对多个连续地址进行读写操作。
        -接口要求：
            -指定起始地址和突发长度
        -好处：
            -利用DDR突发访问特性，提高带宽和效率
    刷新控制（Refresh Control）
        -功能：
            -可选地暴露REFRESH命令的触发接口，用于特殊的手动刷新场景
        -接口要求：
            一般通过一个触发信号告诉控制器执行REFRESH，但底层实现仍由控制器管理
    初始化（Initialization）
        -功能:
            -提供初始化接口，用户可以通过命令重置和重新初始化DDR控制器及内存模块
        -接口要求：
            -开放INIT或RESET命令
