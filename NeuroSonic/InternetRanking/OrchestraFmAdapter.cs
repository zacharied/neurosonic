using System;
using System.Collections.Generic;
using System.Text;
using NeuroSonic.GamePlay.Scoring;
using theori.InternetRanking;

namespace NeuroSonic.InternetRanking
{
    internal struct OrchestraFmAdapter : IInternetRankingScoreAdapter
    {
        public Dictionary<string, dynamic> AdaptScore(object scoreObj)
        {
            var score = (ScoringResult) scoreObj;
            return new Dictionary<string, dynamic>
            {
                {"score", score.Score},
                {"combo", score.MaxCombo},
                {"rate", score.Gauge},
                {
                    "criticals",
                    score.CriticalBtCount + score.PerfectBtCount + score.CriticalFxCount + score.PerfectFxCount +
                    score.PassiveBtCount + score.PassiveFxCount + score.PassiveVolCount
                },
                {"nears", score.EarlyBtCount + score.LateBtCount + score.EarlyFxCount + score.LateFxCount},
                {"errors", score.BadBtCount + score.BadFxCount + score.MissCount},
                {"mods", UInt32.MinValue},
                {"replay", string.Empty}
            };
        }
    }
}
