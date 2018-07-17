pragma solidity ^0.4.24;

contract BattleShips {
   
    /*
    After game is Created, both players commit to their boards
    During the game, the state is either Attack or Reveal
    */
    enum GameState { Created, Attack, Reveal, WinClaimed, Finished }
    
    uint8 public turn; //0 if players[0] turn, 1 if players[1] turn
    GameState public gameState;
    
    address[2] public players;
    address public winner;
    Board[2] public boards;
    Ship[2][10] public ships;
    
    // TODO: set this after every action
    uint256 public lastUpdateHeight;
    
    /*
    coordinates of the last tile that has been attacked
    */
    uint8 public lastX;
    uint8 public lastY;
 
    /*
    commitment is hash of (randomness, x1, y1, x2, y2) 
    where (x1, y1) is the starting coordinate and (x2,y2) is the end coordinate
    x1 <= x2, y1 <= y2
    */
    struct Ship {
        bytes32 commitment;
        uint128 randomness;
        uint8 x1;
        uint8 y1;
        uint8 x2;
        uint8 y2;
        bool sunk;
    }
    
    struct Board {
        /*
        commitment is a hash of (randomness,shipTile)
        randomness, ship are revealed during the game if Tile is hit
        */
        bytes32[10][10] commitments;
        uint128[10][10] randomness;
        bool[10][10] shipTile;
        bool[10][10] revealed;
        bool committed;
    }
    
    /*
    restrict access to players
    */ 
    modifier onlyPlayers() {
        require(msg.sender == players[0] || msg.sender == players[1]);
        _;
    }
    
    /*
    restrict access to player whose turn it is
    */
    modifier onlyPlayerTurn() {
        require(msg.sender == players[turn]);
        _;
    }
    
    /*
    only allow in `state`
    */
    modifier onlyState(GameState state) {
        require(gameState == state);
        _;
    }
    
    event BoardCommit(address indexed player);
    event Attack(address indexed player, uint8 x, uint8 y);
    event Reveal(address indexed player, bool hit);
    event Winner(address indexed player);
    event RevealSink(address indexed player, uint8 shipidx);

    mapping (uint8 => address) playerIndex;

    constructor (address player0, address player1) public {
        players[0] = player0;
        players[1] = player1;
        playerIndex[0] = player0;
        playerIndex[1] = player1;
        gameState = GameState.Created;
    }
    
    
    function declareWinner(uint8 idx) internal {
        winner = players[idx];
        gameState = GameState.Finished;
        emit Winner(winner);
    }
    
    /*
    attacks tile at coordinate (x,y)
    */ 
    function attack(uint8 x, uint8 y) onlyPlayerTurn onlyState(GameState.Attack) public {
        require(0<=x && x<10 && 0<=y && y<10);
        lastY = y;
        lastX = x;
        turn = 1 - turn;
        gameState = GameState.Reveal;
        emit Attack(msg.sender, x, y); 
    }
    
    /*
    reveal last attacked tile if no ship has been sunk by a hit
    */ 
    function reveal(uint128 randomness, bool ship) onlyPlayerTurn() onlyState(GameState.Reveal) public {
        if (keccak256(abi.encodePacked(randomness, ship)) == boards[turn].commitments[lastX][lastY]) {
            boards[turn].shipTile[lastX][lastY] = ship;
            boards[turn].randomness[lastX][lastY] = randomness;
            boards[turn].revealed[lastX][lastY] = true;
            if (ship) {
                turn = turn - 1;
            }
            gameState = GameState.Attack;
            emit Reveal(msg.sender, ship);
        } else {
            declareWinner(turn -1);
        }
    }
    
    function isSunk(uint8 player, uint8 shipidx, uint8 x1, uint8 x2, uint8 y1, uint8 y2) public returns (bool) {
        Ship storage board = ships[player][shipidx];
        require(board.x1 == x1);
        require(board.y1 == y1);
        require(board.x2 == x2);
        require(board.y2 == y2);

        return board.sunk;
    }

    /*
    reveal last attacked tile if a ship has been sunk by a hit
    in that case, the ship also has to be revealed
    */ 
    function revealSink(uint128 fieldRandomness, uint128 shipRandomness, uint8 shipIdx, uint8 shipx1, uint8 shipy1, uint8 shipx2, uint8 shipy2) onlyPlayerTurn() onlyState(GameState.Reveal) public {
        if (keccak256(abi.encodePacked(fieldRandomness, true)) == boards[turn].commitments[lastX][lastY]
                 && keccak256(abi.encodePacked(shipRandomness, shipx1, shipy1, shipx2, shipy2)) == ships[turn][shipIdx].commitment
                 && lastX >= shipx1 && lastX <= shipx2
                 && lastY >= shipy1 && lastY <= shipy2
                 && (shipx1 == shipx2 || shipy1 == shipy2)) {
            boards[turn].shipTile[lastX][lastY] = true;
            boards[turn].randomness[lastX][lastY] = fieldRandomness;
            boards[turn].revealed[lastX][lastY] = true;
             
            ships[turn][shipIdx].randomness = shipRandomness;
            ships[turn][shipIdx].x1 = shipx1;
            ships[turn][shipIdx].y1 = shipy1;
            ships[turn][shipIdx].x2 = shipx2;
            ships[turn][shipIdx].y2 = shipy2;
            ships[turn][shipIdx].sunk = true;
            
            emit RevealSink(msg.sender, shipIdx);
 
            // check that all tiles of the ship have been hit and contain a ship
            for (uint8 x = shipx1; x <= shipx2; x++){
                for (uint8 y = shipy1; y <= shipy2; y++){
                    if (!boards[turn].shipTile[x][y]) {
                        // cheating, either tile hasn't been revealed or indicated water
                        declareWinner(1-turn);
                        return;
                    }
                }
            }   
             
            turn = turn - 1;
            gameState = GameState.Attack;
        } else {
            declareWinner(turn -1);
        }
    }
    
    function claimWin( ) onlyPlayers() public {
         uint8 idx = 0;
         if(msg.sender == players[1]) {
            idx = 1;
         }
         for (uint8 i = 0; i<10; i++) {
             require(ships[1-idx][i].sunk);
         }
         // TODO: check board of winner
         declareWinner(idx);
    }


    function isCommitted(uint8 _player) public view returns (bool) {
        return boards[_player].committed;
    }
   
    /* currently allows players to change the commitments to their board until the other player has also committed */
    function commitBoard(bytes32[10][10] boardCommitments, bytes32[10] shipCommitments) onlyPlayers onlyState(GameState.Created) public {
        uint8 idx = 0;
        if(msg.sender == players[1]) {
            idx = 1;
        }
        boards[idx].commitments = boardCommitments;
        for (uint8 i = 0; i<10;i++) {
            ships[idx][i].commitment = shipCommitments[i];
        }
        boards[idx].committed = true;
        if (boards[0].committed && boards[1].committed) {
            gameState = GameState.Attack;
        }

        emit BoardCommit(msg.sender);
    }
   

    //event DebugCommit(bytes32 shipCommit, bytes32 myCommit, uint128 shipRandom, uint8 shipidx);
    //event DebugShipCoord(uint8 x1, uint8 y1, uint8 x2, uint8 y2);
    event shipsize1();
    event shipsize2();
    event shipsize3();
    event shipsize4();
 
    /*
    checks whether a player has actually placed all ships on the committed board
    the player reveals the ship locations and the blinding factors for all commitments for tiles that contain a ship
    */
    function checkBoard(uint8 idx, uint128[20] shipFieldRandomness, uint128[10] shipRandomness, uint8[10] shipX1, uint8[10] shipY1, uint8[10] shipX2, uint8[10] shipY2)  public {
        uint8 size;
        uint8 revealed;
        uint8 x;
        uint8 y;
        for (uint8 i = 0; i<10; i++) {
            if (!ships[idx][i].sunk) {
                // if the ship has been sunk, the locations have already been checked, otherwise check that they are actually on the board
                size = 0;
                revealed = 0;
                
                // ship has to be tiles in a line, second coordinate has to be larger
                if (!(shipX1[i] <= shipX2[i] && shipY1[i] <= shipY2[i] && (shipX1[i] == shipX2[i] || shipY1[i] == shipY2[i]))) {
                    //cheating
                    declareWinner(1-idx);
                    return;
                }
                //emit DebugCommit(ships[idx][i].commitment,keccak256(abi.encodePacked(shipRandomness[i], shipX1[i], shipY1[i], shipX2[i], shipY2[i])), shipRandomness[i], i);
                //emit DebugShipCoord(shipX1[i], shipY1[i], shipX2[i], shipY2[i]);
                // check ship commitment
                if (keccak256(abi.encodePacked(shipRandomness[i], shipX1[i], shipY1[i], shipX2[i], shipY2[i])) != ships[idx][i].commitment) {
                    //cheating
                    declareWinner(1-idx);
                    return;
                }
                // check tile commitments for each ship size and check that at least one tile per ship was not revealed during the game
                if (i < 4) { 
                    //size 1
                    emit shipsize1();
                    if (boards[idx].revealed[shipX1[i]][shipY1[i]] || !(shipX1[i] == shipX2[i] && shipY1[i] == shipY2[i] && keccak256(abi.encodePacked(shipFieldRandomness[i], true)) == boards[idx].commitments[shipX1[i]][shipY1[i]])) {
                        //cheating
                        declareWinner(1-idx);
                        emit shipsize1();
                        return;
                    }
                } else if (i < 7) {
                    // ship of size 2
                    for (x = shipX1[i]; x <= shipX2[i]; x++){
                        for (y = shipY1[i]; y <= shipY2[i]; y++){
                            size++;
                            if (boards[idx].revealed[x][y]) {
                                // count number of tiles revealed during the game
                                revealed++;
                                if (!boards[idx].shipTile[x][y]) {
                                    // one of the tiles indicated water
                                    declareWinner(1-idx);
                                    emit shipsize2();
                                    return;
                                }
                            }
                            if (keccak256(abi.encodePacked(shipFieldRandomness[4+(i-4)*2+size], true)) != boards[idx].commitments[x][y]){
                                //cheating
                                declareWinner(1-idx);
                                emit shipsize2();
                                return;
                            }
                        }   
                    }
                    if (size != 2) {
                        //cheating
                        declareWinner(1-idx);
                        emit shipsize2();
                        return;
                    }
                } else if (i < 9) {
                    // ship of size 3
                    for (x = shipX1[i]; x <= shipX2[i]; x++){
                        for (y = shipY1[i]; y <= shipY2[i]; y++){
                            size++;
                            if (boards[idx].revealed[x][y]) {
                                // count number of tiles revealed during the game
                                revealed++;
                                if (!boards[idx].shipTile[x][y]) {
                                    // one of the tiles indicated water
                                    declareWinner(1-idx);
                                    emit shipsize3();
                                    return;
                                }
                            }
                            if (keccak256(abi.encodePacked(shipFieldRandomness[10+(i-7)*3+size], true)) != boards[idx].commitments[x][y]){
                                //cheating
                                declareWinner(1-idx);
                                emit shipsize3();
                                return;
                            }
                        }   
                    }
                     if (size != 3) {
                        //cheating
                        declareWinner(1-idx);
                        emit shipsize3();
                        return;
                     }
                } else {
                     // ship of size 4
                    for (x = shipX1[i]; x <= shipX2[i]; x++){
                        for (y = shipY1[i]; y <= shipY2[i]; y++){
                            size++;
                            if (boards[idx].revealed[x][y]) {
                                // count number of tiles revealed during the game
                                revealed++;
                                if (!boards[idx].shipTile[x][y]) {
                                    // one of the tiles indicated water
                                    declareWinner(1-idx);
                                    emit shipsize4();
                                    return;
                                }
                            }
                            if (keccak256(abi.encodePacked(shipFieldRandomness[16+size], true)) != boards[idx].commitments[x][y]){
                                //cheating
                                declareWinner(1-idx);
                                emit shipsize4();
                                return;
                            }
                        }   
                    }
                    if (size != 4) {
                        //cheating
                        declareWinner(1-idx);
                        emit shipsize4();
                        return;
                    }
                }
                //if (revealed == size) {
                //    // the ship should have been revealed during the game but wasn't
                //    declareWinner(1-idx);
                //    return;
                //}
                // add ship coordinates to contract
                ships[idx][i].x1 = shipX1[i];
                ships[idx][i].y1 = shipY1[i];
                ships[idx][i].x2 = shipX2[i];
                ships[idx][i].y2 = shipY2[i];
            }
        }
    }
    
    /*
    Fraud proof for adjacent or overlapping ships
    Can be called during the game or once one player has claimed to win the game
    */
    function adjacentOrOverlapping(uint8 shipIdx1, uint8 shipIdx2) onlyPlayers() public {
        require(gameState != GameState.Finished);
        
        // idx of other player
        uint8 playerIdx = 1;
        if(msg.sender == players[1]) {
            playerIdx = 0;
        }
        require(gameState == GameState.WinClaimed || (ships[playerIdx][shipIdx1].sunk && ships[playerIdx][shipIdx2].sunk));
        bool cheated = (ships[playerIdx][shipIdx2].x1 >= ships[playerIdx][shipIdx1].x1 - 1
                    &&  ships[playerIdx][shipIdx2].x1 <= ships[playerIdx][shipIdx1].x1 + 1
                    &&  ships[playerIdx][shipIdx2].y1 >= ships[playerIdx][shipIdx1].y1 - 1
                    &&  ships[playerIdx][shipIdx2].y1 <= ships[playerIdx][shipIdx1].y1 + 1);
        cheated = cheated ||
                       (ships[playerIdx][shipIdx2].x1 >= ships[playerIdx][shipIdx1].x2 - 1
                    &&  ships[playerIdx][shipIdx2].x1 <= ships[playerIdx][shipIdx1].x2 + 1
                    &&  ships[playerIdx][shipIdx2].y1 >= ships[playerIdx][shipIdx1].y2 - 1
                    &&  ships[playerIdx][shipIdx2].y1 <= ships[playerIdx][shipIdx1].y2 + 1);
        cheated = cheated ||
                       (ships[playerIdx][shipIdx2].x2 >= ships[playerIdx][shipIdx1].x1 - 1
                    &&  ships[playerIdx][shipIdx2].x2 <= ships[playerIdx][shipIdx1].x1 + 1
                    &&  ships[playerIdx][shipIdx2].y2 >= ships[playerIdx][shipIdx1].y1 - 1
                    &&  ships[playerIdx][shipIdx2].y2 <= ships[playerIdx][shipIdx1].y1 + 1);
        cheated = cheated ||
                       (ships[playerIdx][shipIdx2].x2 >= ships[playerIdx][shipIdx1].x2 - 1
                    &&  ships[playerIdx][shipIdx2].x2 <= ships[playerIdx][shipIdx1].x2 + 1
                    &&  ships[playerIdx][shipIdx2].y2 >= ships[playerIdx][shipIdx1].y2 - 1
                    &&  ships[playerIdx][shipIdx2].y2 <= ships[playerIdx][shipIdx1].y2 + 1);
        if (cheated) {
            declareWinner(1-playerIdx);
        }
        
    }
    
    /*
    Allows the players to claim the win if the other player takes too long to take his turn
    */
    function timeout() public onlyPlayers() {
        require(gameState == GameState.Attack || gameState == GameState.Reveal);
        if (block.number > lastUpdateHeight + 20) {
            declareWinner(1-turn);
        }
    }
    
    /*
    Allows the players to finalize the game after the period for fraud proof submission is over
    */
    function finishGame() public onlyPlayers() onlyState(GameState.WinClaimed) {
        if (block.number > lastUpdateHeight + 20) {
            gameState = GameState.Finished;
        }
    }
    
    function setState(uint8 _turn, GameState _state, address _winner, bytes32[2][10][10] boardCommitments, 
            uint128[2][10][10] fieldRandomness, bool[2][10][10] shiptiles, bool[2][10][10] revealedtiles,
            bytes32[2][10] shipCommitments, uint128[2][10] shipRandomness ,uint8[2][2][10] shipX, uint8[2][2][10] shipY, 
            bool[2][10] sunk, uint8 _lastX, uint8 _lastY) public  {
        // TODO: hash and check that this corresponds to hash in state channel contract
        turn = _turn;
        gameState = _state;
        winner = _winner;
        lastX = _lastX;
        lastY = _lastY;
        boards[0].commitments = boardCommitments[0];
        boards[0].randomness = fieldRandomness[0];
        boards[0].shipTile = shiptiles[0];
        boards[0].revealed = revealedtiles[0];
        boards[1].commitments = boardCommitments[1];
        boards[1].randomness = fieldRandomness[1];
        boards[1].shipTile = shiptiles[1];
        boards[1].revealed = revealedtiles[1];
        for (uint8  i = 0; i<10; i++) {
            ships[0][i].commitment = shipCommitments[0][i];
            ships[0][i].randomness = shipRandomness[0][i];
            ships[0][i].x1 = shipX[0][0][i];
            ships[0][i].y1 = shipY[0][0][i];
            ships[0][i].x2 = shipX[0][1][i];
            ships[0][i].y2 = shipY[0][1][i];
            ships[0][i].sunk = sunk[0][i];
            
            ships[1][i].commitment = shipCommitments[1][i];
            ships[1][i].randomness = shipRandomness[1][i];
            ships[1][i].x1 = shipX[1][0][i];
            ships[1][i].y1 = shipY[1][0][i];
            ships[1][i].x2 = shipX[1][1][i];
            ships[1][i].y2 = shipY[1][1][i];
            ships[1][i].sunk = sunk[1][i];
        }
        lastUpdateHeight = block.number;
    }
    
    function getStateHash()  public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            gameState,
            winner,
            lastX,
            lastY
            ));
    }
    
}
